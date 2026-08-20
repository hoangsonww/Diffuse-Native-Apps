import SwiftUI
import WidgetKit

@main
struct DiffuseComplicationBundle: WidgetBundle {
    var body: some Widget {
        ChangeCountWidget(kind: "com.diffuse.watch.complication", store: .watch)
    }
}
