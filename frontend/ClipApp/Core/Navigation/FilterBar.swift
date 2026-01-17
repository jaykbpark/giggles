import SwiftUI

struct FilterBar: View {
    @ObservedObject var viewState: GlobalViewState
    
    var body: some View {
        HStack(spacing: 0) {
            // Sort picker (fixed)
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewState.sortOrder = order
                        }
                    } label: {
                        Label(order.rawValue, systemImage: order.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewState.sortOrder.icon)
                        .font(.system(size: 11, weight: .semibold))
                    
                    Text(viewState.sortOrder.rawValue)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(viewState.sortOrder != .recent ? AppColors.accent : AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(viewState.sortOrder != .recent ? AppColors.accent.opacity(0.12) : AppColors.warmSurface)
                }
            }
            .padding(.leading, 20)
            
            // Divider
            Rectangle()
                .fill(AppColors.timelineLine)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 10)
            
            // Tag chips (scrollable)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewState.allTopics, id: \.self) { tag in
                        TagChip(
                            tag: tag,
                            isSelected: viewState.selectedTags.contains(tag)
                        ) {
                            HapticManager.playLight()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewState.toggleTag(tag)
                            }
                        }
                    }
                    
                    // Clear button at end of scroll (only when filters active)
                    if viewState.hasActiveFilters {
                        Button {
                            HapticManager.playLight()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewState.clearFilters()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AppColors.textSecondary.opacity(0.6))
                        }
                        .padding(.leading, 4)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.trailing, 20)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(tag)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? .white : AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(isSelected ? AnyShapeStyle(AppGradients.accent) : AnyShapeStyle(AppColors.warmSurface))
                        .overlay {
                            if !isSelected {
                                Capsule()
                                    .stroke(AppColors.timelineLine.opacity(0.6), lineWidth: 1)
                            }
                        }
                }
                .scaleEffect(isSelected ? 1.03 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by \(tag)")
    }
}

// MARK: - Preview

#Preview {
    VStack {
        FilterBar(viewState: GlobalViewState())
        Spacer()
    }
    .background(AppColors.warmBackground)
}
