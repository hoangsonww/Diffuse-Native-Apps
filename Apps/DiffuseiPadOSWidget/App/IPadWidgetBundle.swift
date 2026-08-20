import SwiftUI
import WidgetKit

@main
struct IPadWidgetBundle: WidgetBundle {
    var body: some Widget {
        ChangeCountWidget(kind: "com.diffuse.ipados.change-count", store: .iPadOS)
    }
}
