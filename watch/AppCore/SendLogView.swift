// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct SendLogView: View {
    @ObservedObject private var log = SendLog.shared

    var body: some View {
        List(Array(log.lines.enumerated().reversed()), id: \.offset) { entry in
            Text(entry.element)
                .font(.footnote)
        }
        .navigationTitle("Send log")
    }
}
