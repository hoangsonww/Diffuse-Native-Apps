import SwiftUI
import WidgetKit

@main
struct IOSWidgetBundle: WidgetBundle {
    var body: some Widget {
        ChangeCountWidget(kind: "com.diffuse.ios.change-count", store: .iOS)
    }
}
