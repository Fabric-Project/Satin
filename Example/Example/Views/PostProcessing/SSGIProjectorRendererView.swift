import Satin
import SwiftUI

struct SSGIProjectorRendererView: View {
    var body: some View {
        SatinMetalView(renderer: SSGIProjectorRenderer())
            .ignoresSafeArea()
            .navigationTitle("SSGI Projector")
    }
}

struct SSGIProjectorRendererView_Previews: PreviewProvider {
    static var previews: some View {
        SSGIProjectorRendererView()
    }
}
