import Satin
import SwiftUI

struct SSGICornellBoxRendererView: View {
    var body: some View {
        SatinMetalView(renderer: SSGICornellBoxRenderer())
            .ignoresSafeArea()
            .navigationTitle("SSGI Cornell Box")
    }
}

struct SSGICornellBoxRendererView_Previews: PreviewProvider {
    static var previews: some View {
        SSGICornellBoxRendererView()
    }
}
