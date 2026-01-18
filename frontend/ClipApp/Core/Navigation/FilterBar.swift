import SwiftUI

struct FilterBar: View {
    @ObservedObject var viewState: GlobalViewState
    
    var body: some View {
        VStack(spacing: 8) {
            // Row 1: Tab pills (All, Starred)
            HStack(spacing: 8) {
                tabPill(.all)
                tabPill(.starred, icon: "star.fill")
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // Row 2: Sort picker + Tag filters
            HStack(spacing: 10) {
                // Sort picker
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
                
                // Divider
                Rectangle()
                    .fill(AppColors.timelineLine)
                    .frame(width: 1, height: 18)
                
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 6)
    }

    private func tabPill(_ tab: FeedTab, icon: String? = nil) -> some View {
        let isSelected = viewState.selectedFeedTab == tab
        return Button {
            HapticManager.playLight()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                viewState.selectedFeedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? AppColors.accent : AppColors.textPrimary.opacity(0.7))
                }

                Text(tab.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                Capsule()
                    .fill(isSelected ? AppColors.warmSurface : AppColors.warmSurface.opacity(0.6))
                    .overlay {
                        Capsule()
                            .stroke(AppColors.timelineLine.opacity(0.6), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
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
