import SwiftUI

struct FilterBar: View {
    @ObservedObject var viewState: GlobalViewState
    
    var body: some View {
        VStack(spacing: 12) {
            // Sort and filter row
            HStack(spacing: 12) {
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
                    HStack(spacing: 6) {
                        Image(systemName: viewState.sortOrder.icon)
                            .font(.system(size: 12, weight: .semibold))
                        
                        Text(viewState.sortOrder.rawValue)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(viewState.sortOrder != .recent ? AppColors.accent : AppColors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(viewState.sortOrder != .recent ? AppColors.accent.opacity(0.12) : AppColors.warmSurface)
                    }
                }
                
                Spacer()
                
                // Clear filters button (only show when filters active)
                if viewState.hasActiveFilters {
                    Button {
                        HapticManager.playLight()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewState.clearFilters()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Clear")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(AppColors.warmSurface)
                        }
                    }
                }
            }
            
            // Tag chips (horizontal scroll)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20) // Offset to allow edge-to-edge scroll
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white : AppColors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(isSelected ? AppColors.accent : AppColors.warmSurface)
                }
        }
        .buttonStyle(.plain)
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
