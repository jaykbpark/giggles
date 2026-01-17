import SwiftUI

struct SkeletonView: View {
    @State private var isAnimating = false

    var body: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color(.systemGray4), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? 200 : -200)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

struct SkeletonGridCell: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonView()
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct SkeletonListRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonView()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                SkeletonView()
                    .frame(height: 16)
                    .frame(maxWidth: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                SkeletonView()
                    .frame(height: 12)
                    .frame(maxWidth: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                SkeletonView()
                    .frame(height: 12)
                    .frame(maxWidth: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

#Preview("Grid Skeleton") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
        ForEach(0..<9, id: \.self) { _ in
            SkeletonGridCell()
        }
    }
    .padding()
}

#Preview("List Skeleton") {
    VStack(spacing: 0) {
        ForEach(0..<5, id: \.self) { _ in
            SkeletonListRow()
            Divider()
        }
    }
    .padding()
}
