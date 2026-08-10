import SwiftUI

struct AppTourView: View {
    @Bindable var model: AppTourModel
    let anchors: [AppTourTarget: Anchor<CGRect>]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if model.isPresented, let step = model.currentStep {
            GeometryReader { proxy in
                if let anchor = anchors[step.target] {
                    let targetRect = proxy[anchor].insetBy(dx: -6, dy: -6)

                    ZStack {
                        AppTourSpotlightShape(cutout: targetRect, cornerRadius: 17)
                            .fill(
                                Color.black.opacity(colorScheme == .dark ? 0.7 : 0.58),
                                style: FillStyle(eoFill: true)
                            )

                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(AppTheme.accent, lineWidth: 3)
                            .frame(width: targetRect.width, height: targetRect.height)
                            .position(x: targetRect.midX, y: targetRect.midY)

                        tooltip(step: step, targetRect: targetRect, availableSize: proxy.size)
                    }
                    .transition(.opacity)
                    .accessibilityAddTraits(.isModal)
                } else if step.target.isOptional {
                    Color.clear
                        .task(id: step.id) {
                            await model.goForward()
                        }
                }
            }
            .ignoresSafeArea()
            .zIndex(100)
        }
    }

    private func tooltip(step: AppTourStep, targetRect: CGRect, availableSize: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(visibleStepNumber(for: step)) of \(visibleSteps.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Button("Skip") {
                    Task { await model.finish() }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.brandDark)
            }

            Text(step.title)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.ink)

            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button(isLastVisibleStep(step) ? "Done" : "Next") {
                Task {
                    if isLastVisibleStep(step) {
                        await model.finish()
                    } else {
                        await model.goForward()
                    }
                }
            }
            .font(.subheadline.bold())
            .foregroundStyle(AppTheme.accentInk)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(AppTheme.accent, in: Capsule())
        }
        .padding(16)
        .frame(width: min(availableSize.width - 32, 380))
        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
        .position(
            x: availableSize.width / 2,
            y: tooltipCenterY(targetRect: targetRect, availableHeight: availableSize.height)
        )
    }

    private func tooltipCenterY(targetRect: CGRect, availableHeight: CGFloat) -> CGFloat {
        let estimatedHalfHeight: CGFloat = 108
        let spacing: CGFloat = 14

        if targetRect.maxY + estimatedHalfHeight + spacing <= availableHeight {
            return targetRect.maxY + estimatedHalfHeight + spacing
        }

        return max(estimatedHalfHeight + 8, targetRect.minY - estimatedHalfHeight - spacing)
    }

    private var visibleSteps: [AppTourStep] {
        model.steps.filter { step in
            !step.target.isOptional || anchors[step.target] != nil
        }
    }

    private func visibleStepNumber(for step: AppTourStep) -> Int {
        guard let index = visibleSteps.firstIndex(where: { $0.id == step.id }) else { return 1 }
        return index + 1
    }

    private func isLastVisibleStep(_ step: AppTourStep) -> Bool {
        visibleSteps.last?.id == step.id
    }
}
