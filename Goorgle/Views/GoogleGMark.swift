import SwiftUI

/// Stylized four-color "G" mark, evocative of Google's logo without
/// reproducing the actual asset — built from four arcs + a bar.
struct GoogleGMark: View {
    private let blue = Color(red: 0.26, green: 0.52, blue: 0.96)
    private let red = Color(red: 0.92, green: 0.26, blue: 0.21)
    private let yellow = Color(red: 0.98, green: 0.74, blue: 0.02)
    private let green = Color(red: 0.20, green: 0.66, blue: 0.33)

    var body: some View {
        GeometryReader { geo in
            let lineWidth = geo.size.width * 0.22
            ZStack {
                Circle()
                    .trim(from: 0.0, to: 0.72)
                    .stroke(blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0.0, to: 0.22)
                    .stroke(red, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(180))

                Circle()
                    .trim(from: 0.0, to: 0.13)
                    .stroke(yellow, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(126))

                Circle()
                    .trim(from: 0.0, to: 0.22)
                    .stroke(green, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(58))

                Rectangle()
                    .fill(blue)
                    .frame(width: geo.size.width * 0.46, height: lineWidth)
                    .offset(x: geo.size.width * 0.18)
            }
        }
    }
}

#Preview {
    GoogleGMark()
        .frame(width: 40, height: 40)
        .padding()
        .background(Color(red: 0.18, green: 0.51, blue: 0.93))
}
