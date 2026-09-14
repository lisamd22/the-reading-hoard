import SwiftUI

struct OnboardingView: View {
    let onComplete: (OnboardingProfile) -> Void

    @State private var page = 0
    @State private var profile = OnboardingProfile.empty

    var body: some View {
        ZStack {
            HoardTheme.background.ignoresSafeArea()
            decorativeGlow

            VStack(spacing: 24) {
                HStack {
                    Image(systemName: "books.vertical.fill")
                    Text("THE READING HOARD")
                        .font(.caption.weight(.semibold))
                        .tracking(2.2)
                    Spacer()
                    Text("\(page + 1) of 4")
                        .foregroundStyle(HoardTheme.mutedParchment)
                }
                .foregroundStyle(HoardTheme.gold)

                TabView(selection: $page) {
                    welcome.tag(0)
                    selectionPage(
                        eyebrow: "YOUR SHELVES",
                        title: "What stories call to you?",
                        subtitle: "Choose a few genres. The castle will keep learning as your library grows.",
                        options: OnboardingProfile.Genre.allCases,
                        selection: $profile.genres
                    ).tag(1)
                    selectionPage(
                        eyebrow: "FAMILIAR MAGIC",
                        title: "Which details draw you in?",
                        subtitle: "These help us understand why a recommendation feels right for you.",
                        options: OnboardingProfile.Trope.allCases,
                        selection: $profile.tropes
                    ).tag(2)
                    formats.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                Button(action: advance) {
                    HStack {
                        Text(page == 3 ? "Enter the library" : "Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(HoardTheme.ink)
                    .background(HoardTheme.gold, in: RoundedRectangle(cornerRadius: 15))
                }
                .accessibilityHint(page == 3 ? "Finishes onboarding" : "Moves to the next question")
            }
            .padding(24)
        }
        .foregroundStyle(HoardTheme.parchment)
    }

    private var decorativeGlow: some View {
        Circle()
            .fill(HoardTheme.ember.opacity(0.22))
            .frame(width: 330, height: 330)
            .blur(radius: 80)
            .offset(x: 170, y: 320)
            .allowsHitTesting(false)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: "building.columns.fill")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(HoardTheme.gold)
                .accessibilityHidden(true)
            Text("The library has chosen its Keeper.")
                .font(HoardTheme.titleFont(40))
                .fixedSize(horizontal: false, vertical: true)
            Text("Bring it the books you discover. It will remember every recommendation — and why it caught your attention.")
                .font(.title3)
                .foregroundStyle(HoardTheme.mutedParchment)
                .lineSpacing(5)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var formats: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("HOW YOU READ")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(HoardTheme.gold)
            Text("Keep every format together.")
                .font(HoardTheme.titleFont(34))
            Text("Choose all the ways you like to read.")
                .foregroundStyle(HoardTheme.mutedParchment)

            ForEach(OnboardingProfile.ReadingFormat.allCases) { format in
                optionButton(format.rawValue, isSelected: profile.formats.contains(format)) {
                    toggle(format, in: &profile.formats)
                }
            }
            Spacer()
        }
    }

    private func selectionPage<Option: Identifiable & Hashable>(
        eyebrow: String,
        title: String,
        subtitle: String,
        options: [Option],
        selection: Binding<Set<Option>>
    ) -> some View where Option.ID == String, Option: RawRepresentable, Option.RawValue == String {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text(eyebrow)
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(HoardTheme.gold)
            Text(title)
                .font(HoardTheme.titleFont(34))
            Text(subtitle)
                .foregroundStyle(HoardTheme.mutedParchment)
                .padding(.bottom, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                ForEach(options) { option in
                    optionButton(option.rawValue, isSelected: selection.wrappedValue.contains(option)) {
                        var updated = selection.wrappedValue
                        toggle(option, in: &updated)
                        selection.wrappedValue = updated
                    }
                }
            }
            Spacer()
        }
    }

    private func optionButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                if isSelected {
                    Image(systemName: "checkmark")
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(isSelected ? HoardTheme.ink : HoardTheme.parchment)
            .background(
                isSelected ? HoardTheme.gold : HoardTheme.midnight.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(HoardTheme.gold.opacity(isSelected ? 0 : 0.3))
            }
        }
    }

    private func advance() {
        if page < 3 {
            withAnimation { page += 1 }
        } else {
            onComplete(profile)
        }
    }

    private func toggle<Value: Hashable>(_ value: Value, in set: inout Set<Value>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }
}
