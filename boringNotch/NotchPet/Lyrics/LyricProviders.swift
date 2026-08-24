//
//  LyricProviders.swift
//  NotchPet
//
//  Multi-source synced-lyric lookup, the way standalone lyric apps (LyricsX, 歌词捕手, …) do it:
//  the OS only hands us the *metadata* of the playing track (title / artist / duration) via
//  MediaRemote — never the lyrics the player is rendering. So we take that metadata, query several
//  public lyric providers concurrently, and pick the candidate whose duration best matches the
//  track (so we don't grab the wrong version / a live cut / a remix).
//
//  Providers, in rough Chinese-coverage order: NetEase (网易云) → QQ音乐 → Kugou (酷狗) → LRCLIB.
//  For a song played *in* NetEase/QQ, querying that same service returns the identical LRC the app
//  shows — matched by duration it's effectively "the app's own lyrics". NetEase & QQ also carry a
//  translation track (中英对照) which we surface when present.
//

import Foundation

/// One provider's best time-stamped lyric candidate for a track.
struct LyricCandidate {
    let lrc: String              // primary time-stamped LRC (may be empty if only plain text exists)
    let translatedLrc: String?   // optional translation LRC on the same timestamps (中译)
    let durationMs: Int?         // duration the provider reports for this song, for matching
    let title: String?
    let artist: String?
    let source: String           // for logging / tie-breaks
}

enum LyricProviders {
    /// Fetch the best synced-lyric candidate across all providers, matched to the playing track.
    /// - Parameters:
    ///   - durationSec: currently-playing track duration in seconds (0 if unknown).
    ///   - preferredSource: bundle id of the player, so a NetEase-played song prefers NetEase, etc.
    static func best(title: String, artist: String,
                     durationSec: Double, preferredSource: String?) async -> LyricCandidate? {
        let q = title.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        let durMs = durationSec > 0 ? Int(durationSec * 1000) : nil

        // Run every provider concurrently; a slow/failed one never blocks the others.
        async let netease = fetchNetease(title: q, artist: artist)
        async let qq      = fetchQQ(title: q, artist: artist)
        async let kugou   = fetchKugou(title: q, artist: artist, durationMs: durMs)
        async let lrclib  = fetchLRCLIB(title: q, artist: artist)

        let candidates = await [netease, qq, kugou, lrclib].compactMap { $0 }
        guard !candidates.isEmpty else { return nil }

        // Lower score = better. Duration mismatch dominates, then whether it's actually synced,
        // then title/artist agreement, then a small provider/preferred-source tie-break.
        func score(_ c: LyricCandidate) -> Double {
            var s = 0.0
            if let want = durMs, let got = c.durationMs {
                let diffSec = abs(Double(want - got)) / 1000.0
                s += min(diffSec, 60) * 4          // ~4 pts/sec, capped so an unknown-ish match still ranks
            } else {
                s += 12                             // unknown duration on either side: mild penalty
            }
            if c.lrc.contains("[") == false { s += 100 }   // no timestamps → plain text only, worst
            if let ct = c.title, !fuzzyContains(ct, q) && !fuzzyContains(q, ct) { s += 8 }
            s += sourceRank(c.source, preferred: preferredSource)
            return s
        }

        return candidates.min { score($0) < score($1) }
    }

    // MARK: - Scoring helpers

    private static func sourceRank(_ source: String, preferred: String?) -> Double {
        // Boost the provider that matches the app actually playing the song.
        if let p = preferred {
            if p.contains("netease") && source == "netease" { return -3 }
            if p.contains("QQMusic") && source == "qq"      { return -3 }
        }
        switch source {
        case "netease": return 0
        case "qq":      return 1
        case "kugou":   return 2
        default:        return 3   // lrclib
        }
    }

    /// Loose containment ignoring case / diacritics / spacing — titles vary across providers.
    private static func fuzzyContains(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .replacingOccurrences(of: " ", with: "")
        }
        let na = norm(a), nb = norm(b)
        return !nb.isEmpty && na.contains(nb)
    }

    // MARK: - Networking

    private static func get(_ urlString: String, referer: String?) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static func json(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }

    // MARK: - NetEase (网易云)

    private static func fetchNetease(title: String, artist: String) async -> LyricCandidate? {
        let keyword = enc([title, artist].filter { !$0.isEmpty }.joined(separator: " "))
        let searchURL = "https://music.163.com/api/search/get?s=\(keyword)&type=1&limit=5&offset=0"
        guard let root = json(await get(searchURL, referer: "https://music.163.com/")),
              let result = root["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]],
              let song = songs.first,
              let id = song["id"] as? Int else { return nil }

        let durMs = song["duration"] as? Int
        let name = song["name"] as? String
        let artistName = (song["artists"] as? [[String: Any]])?.first?["name"] as? String

        let lyricURL = "https://music.163.com/api/song/lyric?id=\(id)&lv=1&kv=1&tv=1"
        guard let lroot = json(await get(lyricURL, referer: "https://music.163.com/")) else { return nil }
        let lrc = ((lroot["lrc"] as? [String: Any])?["lyric"] as? String) ?? ""
        let tlrc = (lroot["tlyric"] as? [String: Any])?["lyric"] as? String
        guard !lrc.isEmpty else { return nil }
        return LyricCandidate(lrc: lrc, translatedLrc: (tlrc?.isEmpty == false) ? tlrc : nil,
                              durationMs: durMs, title: name, artist: artistName, source: "netease")
    }

    // MARK: - QQ音乐

    private static func fetchQQ(title: String, artist: String) async -> LyricCandidate? {
        let keyword = enc([title, artist].filter { !$0.isEmpty }.joined(separator: " "))
        let searchURL = "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?format=json&p=1&n=5&w=\(keyword)"
        guard let root = json(await get(searchURL, referer: "https://y.qq.com/")),
              let data = root["data"] as? [String: Any],
              let song = data["song"] as? [String: Any],
              let list = song["list"] as? [[String: Any]],
              let first = list.first,
              let mid = first["songmid"] as? String else { return nil }

        let durMs = (first["interval"] as? Int).map { $0 * 1000 }
        let name = first["songname"] as? String
        let artistName = (first["singer"] as? [[String: Any]])?.first?["name"] as? String

        // nobase64=1 → plain LRC; format=json avoids the JSONP wrapper. Referer is mandatory.
        let lyricURL = "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=\(mid)&format=json&nobase64=1&g_tk=5381"
        guard let lroot = json(await get(lyricURL, referer: "https://y.qq.com/portal/player.html")) else { return nil }
        let lrc = (lroot["lyric"] as? String) ?? ""
        let tlrc = lroot["trans"] as? String
        guard !lrc.isEmpty else { return nil }
        return LyricCandidate(lrc: lrc, translatedLrc: (tlrc?.isEmpty == false) ? tlrc : nil,
                              durationMs: durMs, title: name, artist: artistName, source: "qq")
    }

    // MARK: - Kugou (酷狗) — its lyric search takes duration, so version-matching is excellent

    private static func fetchKugou(title: String, artist: String, durationMs: Int?) async -> LyricCandidate? {
        let keyword = enc([title, artist].filter { !$0.isEmpty }.joined(separator: " "))
        let searchURL = "https://mobileservice.kugou.com/api/v3/search/song?format=json&keyword=\(keyword)&page=1&pagesize=5&showtype=1"
        guard let root = json(await get(searchURL, referer: "https://www.kugou.com/")),
              let data = root["data"] as? [String: Any],
              let info = data["info"] as? [[String: Any]],
              let first = info.first,
              let hash = first["hash"] as? String else { return nil }

        let durMs = (first["duration"] as? Int).map { $0 * 1000 } ?? durationMs
        let name = first["songname"] as? String
        let artistName = first["singername"] as? String

        // Resolve the candidate lyric (id + accesskey) matched by duration, then download it.
        let dur = durMs ?? 0
        let krcURL = "https://krcs.kugou.com/search?ver=1&man=yes&client=mobi&hash=\(hash)&duration=\(dur)&album_audio_id="
        guard let kroot = json(await get(krcURL, referer: "https://www.kugou.com/")),
              let cands = kroot["candidates"] as? [[String: Any]],
              let cand = cands.first,
              let id = cand["id"] as? String,
              let accesskey = cand["accesskey"] as? String else { return nil }

        let dlURL = "https://lyrics.kugou.com/download?ver=1&client=pc&id=\(id)&accesskey=\(accesskey)&fmt=lrc&charset=utf8"
        guard let droot = json(await get(dlURL, referer: "https://www.kugou.com/")),
              let content = droot["content"] as? String,
              let decoded = Data(base64Encoded: content),
              let lrc = String(data: decoded, encoding: .utf8), !lrc.isEmpty else { return nil }
        return LyricCandidate(lrc: lrc, translatedLrc: nil,
                              durationMs: durMs, title: name, artist: artistName, source: "kugou")
    }

    // MARK: - LRCLIB (fallback, best for non-Chinese)

    private static func fetchLRCLIB(title: String, artist: String) async -> LyricCandidate? {
        let t = enc(title.folding(options: .diacriticInsensitive, locale: nil))
        let a = enc(artist.folding(options: .diacriticInsensitive, locale: nil))
        let searchURL = "https://lrclib.net/api/search?track_name=\(t)&artist_name=\(a)"
        guard let data = await get(searchURL, referer: nil),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = arr.first else { return nil }

        let synced = (first["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let plain = (first["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lrc = synced.isEmpty ? plain : synced
        guard !lrc.isEmpty else { return nil }
        let durMs = (first["duration"] as? Double).map { Int($0 * 1000) }
        return LyricCandidate(lrc: lrc, translatedLrc: nil, durationMs: durMs,
                              title: first["trackName"] as? String,
                              artist: first["artistName"] as? String, source: "lrclib")
    }
}
