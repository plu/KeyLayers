import SwiftUI

/// A sidebar section's title with its "+" button; shared so every section looks the same.
struct SidebarSectionHeader: View {
  let title: String
  let addLabel: String
  let addIdentifier: String
  let isDisabled: Bool
  let add: () -> Void

  var body: some View {
    HStack {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
      Spacer()
      Button(action: add) {
        Image(systemName: "plus")
          .frame(width: 22, height: 18)
      }
      .buttonStyle(.borderless)
      .help(addLabel)
      .accessibilityLabel(addLabel)
      .accessibilityIdentifier(addIdentifier)
      .disabled(isDisabled)
    }
    .padding(.horizontal, 8)
    .padding(.bottom, 4)
  }
}
