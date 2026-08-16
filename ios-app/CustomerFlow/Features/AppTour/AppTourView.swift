import SwiftUI

struct AppTourView: View {
    @Bindable var model: AppTourModel

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 18)
                stepContent
                Spacer(minLength: 20)
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .interactiveDismissDisabled()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Customer Flow")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Text("\(model.role.title) quick tour")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Button("Skip") {
                Task { await model.finish() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.brand)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        if let step = model.currentStep {
            VStack(spacing: 22) {
                Image(systemName: step.icon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 112, height: 112)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .shadow(color: AppTheme.accent.opacity(0.2), radius: 22, y: 10)

                VStack(spacing: 10) {
                    Text(step.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.center)
                    Text(step.message)
                        .font(.system(size: 17))
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.brand)
                    Text(step.tapHint)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(15)
                .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 7) {
                ForEach(model.steps) { step in
                    Capsule()
                        .fill(step.id == model.currentStep?.id ? AppTheme.brand : AppTheme.muted.opacity(0.25))
                        .frame(width: step.id == model.currentStep?.id ? 24 : 7, height: 7)
                }
            }

            HStack(spacing: 12) {
                if model.currentStepIndex > 0 {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.2)) { model.goBack() }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }

                Button(model.isLastStep ? "Start using the app" : "Next") {
                    if model.isLastStep {
                        Task { await model.goForward() }
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            model.currentStepIndex += 1
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
    }
}
