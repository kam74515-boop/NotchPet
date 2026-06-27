//
//  NotesSettingsView.swift
//  NotchPet
//
//  Settings pane for the Notes scratchpad: editor font size + monospaced toggle.
//

import SwiftUI
import Defaults

struct NotesSettingsView: View {
    @Default(.notesFontSize) private var fontSize
    @Default(.notesMonospaced) private var monospaced

    private let minSize: Double = 10
    private let maxSize: Double = 22

    var body: some View {
        Form {
            Section("Editor") {
                Stepper(value: $fontSize, in: minSize...maxSize, step: 1) {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(fontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Toggle("Monospaced Font", isOn: $monospaced)
            }

            Section("Preview") {
                Text("The quick brown fox jumps over the lazy dog.")
                    .font(monospaced
                          ? .system(size: CGFloat(fontSize), design: .monospaced)
                          : .system(size: CGFloat(fontSize)))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
    }
}
