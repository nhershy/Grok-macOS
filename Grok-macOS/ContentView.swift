//
//  ContentView.swift
//  Grok-macOS
//
//  Created by Nicholas Hershy on 7/8/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var model: WebViewModel

    // The sidebar width is reported live from the page in CSS pixels and
    // its rendered width scales with page zoom, so the pill offset tracks
    // both zoom changes and sidebar collapse/expand.
    private var zoomControlsLeadingInset: CGFloat {
        model.sidebarCSSWidth * CGFloat(model.zoomPercent) / 100 + 24
    }

    var body: some View {
        WebView(model: model)
            .frame(minWidth: 800, minHeight: 600)
            .background(WindowGrabber())
            .overlay(alignment: .bottomLeading) {
                ZoomControls(model: model)
                    .padding(.leading, zoomControlsLeadingInset)
                    .padding(.bottom, 16)
                    .animation(.easeOut(duration: 0.2), value: zoomControlsLeadingInset)
            }
            .navigationTitle(model.pageTitle)
    }
}
