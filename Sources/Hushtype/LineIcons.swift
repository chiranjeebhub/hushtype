import SwiftUI

// Generated from the line icons in the Settings design mockup (24×24 grid, 1.6 stroke, round caps), so
// Settings draws exactly the icons the design shows rather than the nearest SF Symbol.

enum LineIcon: String, CaseIterable {
    case gear, sparkles, book, snippet, clock, shield, mic, keyboard, info, lock, monitor, search, check, updown, warn, cursor, key, cloud, house, plus, minus, arrow, refresh, globe, bell, power, down, wand, hands

    /// The icon's outline on the design's 24×24 grid.
    var path: Path {
        var p = Path()
        switch self {
        case .gear:
            p.move(to: CGPoint(x: 12.22, y: 2))
            p.addLine(to: CGPoint(x: 11.78, y: 2))
            p.addCurve(to: CGPoint(x: 9.78, y: 4), control1: CGPoint(x: 10.675, y: 2), control2: CGPoint(x: 9.78, y: 2.895))
            p.addLine(to: CGPoint(x: 9.78, y: 4.18))
            p.addCurve(to: CGPoint(x: 8.78, y: 5.91), control1: CGPoint(x: 9.779, y: 4.894), control2: CGPoint(x: 9.398, y: 5.553))
            p.addLine(to: CGPoint(x: 8.35, y: 6.16))
            p.addCurve(to: CGPoint(x: 6.35, y: 6.16), control1: CGPoint(x: 7.731, y: 6.517), control2: CGPoint(x: 6.969, y: 6.517))
            p.addLine(to: CGPoint(x: 6.2, y: 6.08))
            p.addCurve(to: CGPoint(x: 3.47, y: 6.81), control1: CGPoint(x: 5.244, y: 5.529), control2: CGPoint(x: 4.023, y: 5.855))
            p.addLine(to: CGPoint(x: 3.25, y: 7.19))
            p.addCurve(to: CGPoint(x: 3.98, y: 9.92), control1: CGPoint(x: 2.699, y: 8.146), control2: CGPoint(x: 3.025, y: 9.367))
            p.addLine(to: CGPoint(x: 4.13, y: 10.02))
            p.addCurve(to: CGPoint(x: 5.13, y: 11.74), control1: CGPoint(x: 4.745, y: 10.375), control2: CGPoint(x: 5.126, y: 11.03))
            p.addLine(to: CGPoint(x: 5.13, y: 12.25))
            p.addCurve(to: CGPoint(x: 4.13, y: 13.99), control1: CGPoint(x: 5.133, y: 12.967), control2: CGPoint(x: 4.751, y: 13.631))
            p.addLine(to: CGPoint(x: 3.98, y: 14.08))
            p.addCurve(to: CGPoint(x: 3.25, y: 16.81), control1: CGPoint(x: 3.025, y: 14.633), control2: CGPoint(x: 2.699, y: 15.854))
            p.addLine(to: CGPoint(x: 3.47, y: 17.19))
            p.addCurve(to: CGPoint(x: 6.2, y: 17.92), control1: CGPoint(x: 4.023, y: 18.145), control2: CGPoint(x: 5.244, y: 18.471))
            p.addLine(to: CGPoint(x: 6.35, y: 17.84))
            p.addCurve(to: CGPoint(x: 8.35, y: 17.84), control1: CGPoint(x: 6.969, y: 17.483), control2: CGPoint(x: 7.731, y: 17.483))
            p.addLine(to: CGPoint(x: 8.78, y: 18.09))
            p.addCurve(to: CGPoint(x: 9.78, y: 19.82), control1: CGPoint(x: 9.398, y: 18.447), control2: CGPoint(x: 9.779, y: 19.106))
            p.addLine(to: CGPoint(x: 9.78, y: 20))
            p.addCurve(to: CGPoint(x: 11.78, y: 22), control1: CGPoint(x: 9.78, y: 21.105), control2: CGPoint(x: 10.675, y: 22))
            p.addLine(to: CGPoint(x: 12.22, y: 22))
            p.addCurve(to: CGPoint(x: 14.22, y: 20), control1: CGPoint(x: 13.325, y: 22), control2: CGPoint(x: 14.22, y: 21.105))
            p.addLine(to: CGPoint(x: 14.22, y: 19.82))
            p.addCurve(to: CGPoint(x: 15.22, y: 18.09), control1: CGPoint(x: 14.221, y: 19.106), control2: CGPoint(x: 14.602, y: 18.447))
            p.addLine(to: CGPoint(x: 15.65, y: 17.84))
            p.addCurve(to: CGPoint(x: 17.65, y: 17.84), control1: CGPoint(x: 16.269, y: 17.483), control2: CGPoint(x: 17.031, y: 17.483))
            p.addLine(to: CGPoint(x: 17.8, y: 17.92))
            p.addCurve(to: CGPoint(x: 20.53, y: 17.19), control1: CGPoint(x: 18.756, y: 18.471), control2: CGPoint(x: 19.977, y: 18.145))
            p.addLine(to: CGPoint(x: 20.75, y: 16.8))
            p.addCurve(to: CGPoint(x: 20.02, y: 14.07), control1: CGPoint(x: 21.301, y: 15.844), control2: CGPoint(x: 20.975, y: 14.623))
            p.addLine(to: CGPoint(x: 19.87, y: 13.99))
            p.addCurve(to: CGPoint(x: 18.87, y: 12.25), control1: CGPoint(x: 19.249, y: 13.631), control2: CGPoint(x: 18.867, y: 12.967))
            p.addLine(to: CGPoint(x: 18.87, y: 11.75))
            p.addCurve(to: CGPoint(x: 19.87, y: 10.01), control1: CGPoint(x: 18.867, y: 11.033), control2: CGPoint(x: 19.249, y: 10.369))
            p.addLine(to: CGPoint(x: 20.02, y: 9.92))
            p.addCurve(to: CGPoint(x: 20.75, y: 7.19), control1: CGPoint(x: 20.975, y: 9.367), control2: CGPoint(x: 21.301, y: 8.146))
            p.addLine(to: CGPoint(x: 20.53, y: 6.81))
            p.addCurve(to: CGPoint(x: 17.8, y: 6.08), control1: CGPoint(x: 19.977, y: 5.855), control2: CGPoint(x: 18.756, y: 5.529))
            p.addLine(to: CGPoint(x: 17.65, y: 6.16))
            p.addCurve(to: CGPoint(x: 15.65, y: 6.16), control1: CGPoint(x: 17.031, y: 6.517), control2: CGPoint(x: 16.269, y: 6.517))
            p.addLine(to: CGPoint(x: 15.22, y: 5.91))
            p.addCurve(to: CGPoint(x: 14.22, y: 4.18), control1: CGPoint(x: 14.602, y: 5.553), control2: CGPoint(x: 14.221, y: 4.894))
            p.addLine(to: CGPoint(x: 14.22, y: 4))
            p.addCurve(to: CGPoint(x: 12.22, y: 2), control1: CGPoint(x: 14.22, y: 2.895), control2: CGPoint(x: 13.325, y: 2))
            p.closeSubpath()
            p.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))
        case .sparkles:
            p.move(to: CGPoint(x: 11, y: 3))
            p.addLine(to: CGPoint(x: 12.9, y: 8.6))
            p.addLine(to: CGPoint(x: 18.5, y: 10.5))
            p.addLine(to: CGPoint(x: 12.9, y: 12.4))
            p.addLine(to: CGPoint(x: 11, y: 18))
            p.addLine(to: CGPoint(x: 9.1, y: 12.4))
            p.addLine(to: CGPoint(x: 3.5, y: 10.5))
            p.addLine(to: CGPoint(x: 9.1, y: 8.6))
            p.closeSubpath()
            p.move(to: CGPoint(x: 19, y: 14))
            p.addLine(to: CGPoint(x: 19.7, y: 16))
            p.addLine(to: CGPoint(x: 21.7, y: 16.7))
            p.addLine(to: CGPoint(x: 19.7, y: 17.4))
            p.addLine(to: CGPoint(x: 19, y: 19.4))
            p.addLine(to: CGPoint(x: 18.3, y: 17.4))
            p.addLine(to: CGPoint(x: 16.3, y: 16.7))
            p.addLine(to: CGPoint(x: 18.3, y: 16))
            p.closeSubpath()
        case .book:
            p.move(to: CGPoint(x: 4, y: 19.5))
            p.addCurve(to: CGPoint(x: 6.5, y: 17), control1: CGPoint(x: 4, y: 18.119), control2: CGPoint(x: 5.119, y: 17))
            p.addLine(to: CGPoint(x: 20, y: 17))
            p.addLine(to: CGPoint(x: 20, y: 3))
            p.addLine(to: CGPoint(x: 6.5, y: 3))
            p.addCurve(to: CGPoint(x: 4, y: 5.5), control1: CGPoint(x: 5.119, y: 3), control2: CGPoint(x: 4, y: 4.119))
            p.closeSubpath()
            p.move(to: CGPoint(x: 6.5, y: 17))
            p.addCurve(to: CGPoint(x: 4, y: 19.5), control1: CGPoint(x: 5.119, y: 17), control2: CGPoint(x: 4, y: 18.119))
            p.addCurve(to: CGPoint(x: 6.5, y: 22), control1: CGPoint(x: 4, y: 20.881), control2: CGPoint(x: 5.119, y: 22))
            p.addLine(to: CGPoint(x: 20, y: 22))
            p.addLine(to: CGPoint(x: 20, y: 17))
        case .snippet:
            p.move(to: CGPoint(x: 4, y: 6))
            p.addLine(to: CGPoint(x: 15, y: 6))
            p.move(to: CGPoint(x: 4, y: 12))
            p.addLine(to: CGPoint(x: 15, y: 12))
            p.move(to: CGPoint(x: 4, y: 18))
            p.addLine(to: CGPoint(x: 11, y: 18))
            p.move(to: CGPoint(x: 18, y: 14))
            p.addLine(to: CGPoint(x: 18, y: 22))
            p.move(to: CGPoint(x: 14, y: 18))
            p.addLine(to: CGPoint(x: 22, y: 18))
        case .clock:
            p.move(to: CGPoint(x: 3, y: 12))
            p.addCurve(to: CGPoint(x: 10.115, y: 20.809), control1: CGPoint(x: 2.996, y: 16.247), control2: CGPoint(x: 5.962, y: 19.919))
            p.addCurve(to: CGPoint(x: 20.214, y: 15.686), control1: CGPoint(x: 14.269, y: 21.698), control2: CGPoint(x: 18.478, y: 19.563))
            p.addCurve(to: CGPoint(x: 17.31, y: 4.741), control1: CGPoint(x: 21.95, y: 11.81), control2: CGPoint(x: 20.739, y: 7.247))
            p.addCurve(to: CGPoint(x: 6, y: 5.3), control1: CGPoint(x: 13.88, y: 2.236), control2: CGPoint(x: 9.166, y: 2.468))
            p.addLine(to: CGPoint(x: 3, y: 8))
            p.move(to: CGPoint(x: 3, y: 3))
            p.addLine(to: CGPoint(x: 3, y: 8))
            p.addLine(to: CGPoint(x: 8, y: 8))
            p.move(to: CGPoint(x: 12, y: 7))
            p.addLine(to: CGPoint(x: 12, y: 12))
            p.addLine(to: CGPoint(x: 15, y: 14))
        case .shield:
            p.move(to: CGPoint(x: 12, y: 22))
            p.addCurve(to: CGPoint(x: 20, y: 12), control1: CGPoint(x: 12, y: 22), control2: CGPoint(x: 20, y: 18))
            p.addLine(to: CGPoint(x: 20, y: 5))
            p.addLine(to: CGPoint(x: 12, y: 2))
            p.addLine(to: CGPoint(x: 4, y: 5))
            p.addLine(to: CGPoint(x: 4, y: 12))
            p.addCurve(to: CGPoint(x: 12, y: 22), control1: CGPoint(x: 4, y: 18), control2: CGPoint(x: 12, y: 22))
            p.closeSubpath()
            p.move(to: CGPoint(x: 9, y: 12))
            p.addLine(to: CGPoint(x: 11, y: 14))
            p.addLine(to: CGPoint(x: 15, y: 10))
        case .mic:
            p.move(to: CGPoint(x: 12, y: 2))
            p.addCurve(to: CGPoint(x: 9, y: 5), control1: CGPoint(x: 10.343, y: 2), control2: CGPoint(x: 9, y: 3.343))
            p.addLine(to: CGPoint(x: 9, y: 12))
            p.addCurve(to: CGPoint(x: 12, y: 15), control1: CGPoint(x: 9, y: 13.657), control2: CGPoint(x: 10.343, y: 15))
            p.addCurve(to: CGPoint(x: 15, y: 12), control1: CGPoint(x: 13.657, y: 15), control2: CGPoint(x: 15, y: 13.657))
            p.addLine(to: CGPoint(x: 15, y: 5))
            p.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 15, y: 3.343), control2: CGPoint(x: 13.657, y: 2))
            p.closeSubpath()
            p.move(to: CGPoint(x: 19, y: 10))
            p.addLine(to: CGPoint(x: 19, y: 12))
            p.addCurve(to: CGPoint(x: 12, y: 19), control1: CGPoint(x: 19, y: 15.866), control2: CGPoint(x: 15.866, y: 19))
            p.addCurve(to: CGPoint(x: 5, y: 12), control1: CGPoint(x: 8.134, y: 19), control2: CGPoint(x: 5, y: 15.866))
            p.addLine(to: CGPoint(x: 5, y: 10))
            p.move(to: CGPoint(x: 12, y: 19))
            p.addLine(to: CGPoint(x: 12, y: 22))
        case .keyboard:
            p.addRoundedRect(in: CGRect(x: 2, y: 6, width: 20, height: 12), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: CGPoint(x: 6, y: 10))
            p.addLine(to: CGPoint(x: 6.01, y: 10))
            p.move(to: CGPoint(x: 10, y: 10))
            p.addLine(to: CGPoint(x: 10.01, y: 10))
            p.move(to: CGPoint(x: 14, y: 10))
            p.addLine(to: CGPoint(x: 14.01, y: 10))
            p.move(to: CGPoint(x: 18, y: 10))
            p.addLine(to: CGPoint(x: 18.01, y: 10))
            p.move(to: CGPoint(x: 7, y: 14))
            p.addLine(to: CGPoint(x: 17, y: 14))
        case .info:
            p.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            p.move(to: CGPoint(x: 12, y: 16))
            p.addLine(to: CGPoint(x: 12, y: 11))
            p.move(to: CGPoint(x: 12, y: 8))
            p.addLine(to: CGPoint(x: 12.01, y: 8))
        case .lock:
            p.addRoundedRect(in: CGRect(x: 5, y: 11, width: 14, height: 10), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: CGPoint(x: 8, y: 11))
            p.addLine(to: CGPoint(x: 8, y: 7))
            p.addCurve(to: CGPoint(x: 12, y: 3), control1: CGPoint(x: 8, y: 4.791), control2: CGPoint(x: 9.791, y: 3))
            p.addCurve(to: CGPoint(x: 16, y: 7), control1: CGPoint(x: 14.209, y: 3), control2: CGPoint(x: 16, y: 4.791))
            p.addLine(to: CGPoint(x: 16, y: 11))
        case .monitor:
            p.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 12), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: CGPoint(x: 8, y: 20))
            p.addLine(to: CGPoint(x: 16, y: 20))
            p.move(to: CGPoint(x: 12, y: 16))
            p.addLine(to: CGPoint(x: 12, y: 20))
        case .search:
            p.addEllipse(in: CGRect(x: 4, y: 4, width: 14, height: 14))
            p.move(to: CGPoint(x: 20, y: 20))
            p.addLine(to: CGPoint(x: 16.5, y: 16.5))
        case .check:
            p.move(to: CGPoint(x: 5, y: 12))
            p.addLine(to: CGPoint(x: 10, y: 17))
            p.addLine(to: CGPoint(x: 19, y: 7))
        case .updown:
            p.move(to: CGPoint(x: 7, y: 9))
            p.addLine(to: CGPoint(x: 12, y: 4))
            p.addLine(to: CGPoint(x: 17, y: 9))
            p.move(to: CGPoint(x: 7, y: 15))
            p.addLine(to: CGPoint(x: 12, y: 20))
            p.addLine(to: CGPoint(x: 17, y: 15))
        case .warn:
            p.move(to: CGPoint(x: 10.3, y: 3.9))
            p.addLine(to: CGPoint(x: 1.8, y: 18))
            p.addCurve(to: CGPoint(x: 1.792, y: 19.986), control1: CGPoint(x: 1.445, y: 18.614), control2: CGPoint(x: 1.442, y: 19.37))
            p.addCurve(to: CGPoint(x: 3.5, y: 21), control1: CGPoint(x: 2.141, y: 20.603), control2: CGPoint(x: 2.791, y: 20.989))
            p.addLine(to: CGPoint(x: 20.5, y: 21))
            p.addCurve(to: CGPoint(x: 22.208, y: 19.986), control1: CGPoint(x: 21.209, y: 20.989), control2: CGPoint(x: 21.859, y: 20.603))
            p.addCurve(to: CGPoint(x: 22.2, y: 18), control1: CGPoint(x: 22.558, y: 19.37), control2: CGPoint(x: 22.555, y: 18.614))
            p.addLine(to: CGPoint(x: 13.7, y: 3.9))
            p.addCurve(to: CGPoint(x: 12, y: 2.954), control1: CGPoint(x: 13.335, y: 3.312), control2: CGPoint(x: 12.692, y: 2.954))
            p.addCurve(to: CGPoint(x: 10.3, y: 3.9), control1: CGPoint(x: 11.308, y: 2.954), control2: CGPoint(x: 10.665, y: 3.312))
            p.closeSubpath()
            p.move(to: CGPoint(x: 12, y: 9))
            p.addLine(to: CGPoint(x: 12, y: 13))
            p.move(to: CGPoint(x: 12, y: 17))
            p.addLine(to: CGPoint(x: 12.01, y: 17))
        case .cursor:
            p.move(to: CGPoint(x: 4, y: 4))
            p.addLine(to: CGPoint(x: 11, y: 21))
            p.addLine(to: CGPoint(x: 13.5, y: 13.5))
            p.addLine(to: CGPoint(x: 21, y: 11))
            p.closeSubpath()
        case .key:
            p.addEllipse(in: CGRect(x: 3, y: 11, width: 9, height: 9))
            p.move(to: CGPoint(x: 10.7, y: 12.3))
            p.addLine(to: CGPoint(x: 20, y: 3))
            p.move(to: CGPoint(x: 17, y: 6))
            p.addLine(to: CGPoint(x: 20, y: 9))
            p.move(to: CGPoint(x: 14, y: 9))
            p.addLine(to: CGPoint(x: 16, y: 11))
        case .cloud:
            p.move(to: CGPoint(x: 17.5, y: 19))
            p.addCurve(to: CGPoint(x: 21.547, y: 16.306), control1: CGPoint(x: 19.26, y: 18.971), control2: CGPoint(x: 20.84, y: 17.918))
            p.addCurve(to: CGPoint(x: 20.783, y: 11.505), control1: CGPoint(x: 22.253, y: 14.694), control2: CGPoint(x: 21.954, y: 12.818))
            p.addCurve(to: CGPoint(x: 16.1, y: 10.2), control1: CGPoint(x: 19.611, y: 10.192), control2: CGPoint(x: 17.782, y: 9.682))
            p.addCurve(to: CGPoint(x: 9.388, y: 5.778), control1: CGPoint(x: 15.326, y: 7.224), control2: CGPoint(x: 12.428, y: 5.314))
            p.addCurve(to: CGPoint(x: 4.3, y: 12), control1: CGPoint(x: 6.348, y: 6.242), control2: CGPoint(x: 4.151, y: 8.929))
            p.addCurve(to: CGPoint(x: 1.9, y: 16.6), control1: CGPoint(x: 2.367, y: 12.608), control2: CGPoint(x: 1.292, y: 14.667))
            p.addCurve(to: CGPoint(x: 6.5, y: 19), control1: CGPoint(x: 2.508, y: 18.533), control2: CGPoint(x: 4.567, y: 19.608))
            p.closeSubpath()
        case .house:
            p.move(to: CGPoint(x: 3, y: 10.5))
            p.addLine(to: CGPoint(x: 12, y: 3))
            p.addLine(to: CGPoint(x: 21, y: 10.5))
            p.addLine(to: CGPoint(x: 21, y: 20))
            p.addCurve(to: CGPoint(x: 20, y: 21), control1: CGPoint(x: 21, y: 20.552), control2: CGPoint(x: 20.552, y: 21))
            p.addLine(to: CGPoint(x: 15, y: 21))
            p.addLine(to: CGPoint(x: 15, y: 15))
            p.addLine(to: CGPoint(x: 9, y: 15))
            p.addLine(to: CGPoint(x: 9, y: 21))
            p.addLine(to: CGPoint(x: 4, y: 21))
            p.addCurve(to: CGPoint(x: 3, y: 20), control1: CGPoint(x: 3.448, y: 21), control2: CGPoint(x: 3, y: 20.552))
            p.closeSubpath()
        case .plus:
            p.move(to: CGPoint(x: 12, y: 5))
            p.addLine(to: CGPoint(x: 12, y: 19))
            p.move(to: CGPoint(x: 5, y: 12))
            p.addLine(to: CGPoint(x: 19, y: 12))
        case .minus:
            p.move(to: CGPoint(x: 5, y: 12))
            p.addLine(to: CGPoint(x: 19, y: 12))
        case .arrow:
            p.move(to: CGPoint(x: 5, y: 12))
            p.addLine(to: CGPoint(x: 19, y: 12))
            p.move(to: CGPoint(x: 13, y: 6))
            p.addLine(to: CGPoint(x: 19, y: 12))
            p.addLine(to: CGPoint(x: 13, y: 18))
        case .refresh:
            p.move(to: CGPoint(x: 21, y: 12))
            p.addCurve(to: CGPoint(x: 15.389, y: 20.413), control1: CGPoint(x: 21.031, y: 15.689), control2: CGPoint(x: 18.807, y: 19.024))
            p.addCurve(to: CGPoint(x: 5.5, y: 18.3), control1: CGPoint(x: 11.971, y: 21.802), control2: CGPoint(x: 8.052, y: 20.965))
            p.addLine(to: CGPoint(x: 3, y: 16))
            p.move(to: CGPoint(x: 3, y: 12))
            p.addCurve(to: CGPoint(x: 8.611, y: 3.587), control1: CGPoint(x: 2.969, y: 8.311), control2: CGPoint(x: 5.193, y: 4.976))
            p.addCurve(to: CGPoint(x: 18.5, y: 5.7), control1: CGPoint(x: 12.029, y: 2.198), control2: CGPoint(x: 15.948, y: 3.035))
            p.addLine(to: CGPoint(x: 21, y: 8))
            p.move(to: CGPoint(x: 21, y: 3))
            p.addLine(to: CGPoint(x: 21, y: 8))
            p.addLine(to: CGPoint(x: 16, y: 8))
            p.move(to: CGPoint(x: 3, y: 21))
            p.addLine(to: CGPoint(x: 3, y: 16))
            p.addLine(to: CGPoint(x: 8, y: 16))
        case .globe:
            p.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            p.move(to: CGPoint(x: 3, y: 12))
            p.addLine(to: CGPoint(x: 21, y: 12))
            p.move(to: CGPoint(x: 12, y: 3))
            p.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 16.368, y: 8.205), control2: CGPoint(x: 16.368, y: 15.795))
            p.move(to: CGPoint(x: 12, y: 3))
            p.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 7.632, y: 8.205), control2: CGPoint(x: 7.632, y: 15.795))
        case .bell:
            p.move(to: CGPoint(x: 6, y: 8))
            p.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 6, y: 4.686), control2: CGPoint(x: 8.686, y: 2))
            p.addCurve(to: CGPoint(x: 18, y: 8), control1: CGPoint(x: 15.314, y: 2), control2: CGPoint(x: 18, y: 4.686))
            p.addCurve(to: CGPoint(x: 21, y: 17), control1: CGPoint(x: 18, y: 15), control2: CGPoint(x: 21, y: 17))
            p.addLine(to: CGPoint(x: 3, y: 17))
            p.addCurve(to: CGPoint(x: 6, y: 8), control1: CGPoint(x: 3, y: 17), control2: CGPoint(x: 6, y: 15))
            p.move(to: CGPoint(x: 10.3, y: 21))
            p.addCurve(to: CGPoint(x: 12, y: 22.051), control1: CGPoint(x: 10.622, y: 21.644), control2: CGPoint(x: 11.28, y: 22.051))
            p.addCurve(to: CGPoint(x: 13.7, y: 21), control1: CGPoint(x: 12.72, y: 22.051), control2: CGPoint(x: 13.378, y: 21.644))
        case .power:
            p.move(to: CGPoint(x: 12, y: 2))
            p.addLine(to: CGPoint(x: 12, y: 12))
            p.move(to: CGPoint(x: 18.4, y: 6.6))
            p.addCurve(to: CGPoint(x: 18.352, y: 19.304), control1: CGPoint(x: 21.885, y: 10.125), control2: CGPoint(x: 21.864, y: 15.805))
            p.addCurve(to: CGPoint(x: 5.648, y: 19.304), control1: CGPoint(x: 14.84, y: 22.802), control2: CGPoint(x: 9.16, y: 22.802))
            p.addCurve(to: CGPoint(x: 5.6, y: 6.6), control1: CGPoint(x: 2.136, y: 15.805), control2: CGPoint(x: 2.115, y: 10.125))
        case .down:
            p.move(to: CGPoint(x: 12, y: 3))
            p.addLine(to: CGPoint(x: 12, y: 15))
            p.move(to: CGPoint(x: 7, y: 10))
            p.addLine(to: CGPoint(x: 12, y: 15))
            p.addLine(to: CGPoint(x: 17, y: 10))
            p.move(to: CGPoint(x: 5, y: 21))
            p.addLine(to: CGPoint(x: 19, y: 21))
        case .wand:
            p.move(to: CGPoint(x: 15, y: 4))
            p.addLine(to: CGPoint(x: 15, y: 2))
            p.move(to: CGPoint(x: 15, y: 10))
            p.addLine(to: CGPoint(x: 15, y: 8))
            p.move(to: CGPoint(x: 12, y: 5))
            p.addLine(to: CGPoint(x: 10, y: 5))
            p.move(to: CGPoint(x: 20, y: 5))
            p.addLine(to: CGPoint(x: 18, y: 5))
            p.move(to: CGPoint(x: 3, y: 21))
            p.addLine(to: CGPoint(x: 15, y: 9))
        case .hands:
            p.move(to: CGPoint(x: 7, y: 11))
            p.addLine(to: CGPoint(x: 7, y: 6))
            p.addCurve(to: CGPoint(x: 9, y: 4), control1: CGPoint(x: 7, y: 4.895), control2: CGPoint(x: 7.895, y: 4))
            p.addCurve(to: CGPoint(x: 11, y: 6), control1: CGPoint(x: 10.105, y: 4), control2: CGPoint(x: 11, y: 4.895))
            p.addLine(to: CGPoint(x: 11, y: 11))
            p.move(to: CGPoint(x: 11, y: 10))
            p.addLine(to: CGPoint(x: 11, y: 4))
            p.addCurve(to: CGPoint(x: 13, y: 2), control1: CGPoint(x: 11, y: 2.895), control2: CGPoint(x: 11.895, y: 2))
            p.addCurve(to: CGPoint(x: 15, y: 4), control1: CGPoint(x: 14.105, y: 2), control2: CGPoint(x: 15, y: 2.895))
            p.addLine(to: CGPoint(x: 15, y: 10))
            p.move(to: CGPoint(x: 15, y: 10))
            p.addLine(to: CGPoint(x: 15, y: 6))
            p.addCurve(to: CGPoint(x: 17, y: 4), control1: CGPoint(x: 15, y: 4.895), control2: CGPoint(x: 15.895, y: 4))
            p.addCurve(to: CGPoint(x: 19, y: 6), control1: CGPoint(x: 18.105, y: 4), control2: CGPoint(x: 19, y: 4.895))
            p.addLine(to: CGPoint(x: 19, y: 14))
            p.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 19, y: 17.866), control2: CGPoint(x: 15.866, y: 21))
            p.addCurve(to: CGPoint(x: 5, y: 14), control1: CGPoint(x: 8.134, y: 21), control2: CGPoint(x: 5, y: 17.866))
            p.addLine(to: CGPoint(x: 5, y: 12))
            p.addCurve(to: CGPoint(x: 7, y: 10), control1: CGPoint(x: 5, y: 10.895), control2: CGPoint(x: 5.895, y: 10))
        }
        return p
    }
}

extension LineIcon {
    /// The design icon that stands in for an SF Symbol name, when the design has one.
    init?(symbol: String) {
        switch symbol {
        case "house": self = .house
        case "keyboard", "keyboard.fill": self = .keyboard
        case "sparkles": self = .sparkles
        case "character.book.closed", "book": self = .book
        case "text.badge.plus": self = .snippet
        case "clock", "clock.arrow.circlepath": self = .clock
        case "lock.shield", "shield": self = .shield
        case "gearshape": self = .gear
        case "magnifyingglass": self = .search
        case "mic", "mic.fill": self = .mic
        case "globe": self = .globe
        case "key": self = .key
        case "macwindow": self = .monitor
        case "hand.raised": self = .hands
        case "speaker.wave.2": self = .bell
        case "wand.and.stars": self = .wand
        case "lock": self = .lock
        case "icloud": self = .cloud
        case "info.circle": self = .info
        case "checkmark": self = .check
        case "arrow.right": self = .arrow
        case "arrow.clockwise": self = .refresh
        case "arrow.down.circle", "arrow.down.to.line": self = .down
        case "power": self = .power
        case "plus": self = .plus
        case "minus": self = .minus
        case "text.cursor": self = .cursor
        case "exclamationmark.triangle", "exclamationmark.triangle.fill": self = .warn
        default: return nil
        }
    }
}

private struct LineIconShape: Shape {
    let icon: LineIcon

    func path(in rect: CGRect) -> Path {
        icon.path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 24, y: rect.height / 24))
    }
}

/// One of the design's line icons at `size` points, drawn in the current foreground style. Names
/// the design has no icon for fall back to the SF Symbol of that name.
struct Icon: View {
    let symbol: String
    var size: CGFloat = 16

    init(_ symbol: String, size: CGFloat = 16) {
        self.symbol = symbol
        self.size = size
    }

    var body: some View {
        if let icon = LineIcon(symbol: symbol) ?? LineIcon(rawValue: symbol) {
            LineIconShape(icon: icon)
                .stroke(style: StrokeStyle(lineWidth: 1.6 * size / 24, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
        } else {
            Image(systemName: symbol).font(.system(size: size * 0.82))
                .frame(width: size, height: size)
        }
    }
}
