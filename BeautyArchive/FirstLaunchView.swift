import SwiftUI

struct FirstLaunchView: View {
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("B/ONE")
                    .font(.system(size: 54, weight: .regular, design: .serif))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 10)

                Text("Beautyを、ひとつに。")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 14)

                Text("美容の記録、写真、アイテム、次の予定を一つの場所に。残した記録が、次の美容行動に役立ちます。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 36)

                VStack(alignment: .leading, spacing: 24) {
                    introductionRow(
                        "記録はこのiPhoneに",
                        detail: "アカウント登録なしで、すぐに使い始められます。",
                        symbol: "iphone"
                    )
                    introductionRow(
                        "iCloudで端末間に",
                        detail: "iCloudを利用できる場合は、同じApple Accountの端末で記録を同期します。",
                        symbol: "icloud"
                    )
                    introductionRow(
                        "Google連携は任意",
                        detail: "Googleカレンダーを使う場合だけ、設定から連携できます。",
                        symbol: "calendar"
                    )
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 52)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onStart) {
                Text("はじめる")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.glassProminent)
            .tint(Color(uiColor: .label))
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(.regularMaterial)
        }
    }

    private func introductionRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    FirstLaunchView(onStart: {})
}
