//
//  ContentView.swift
//  Grok-macOS
//
//  Created by Nicholas Hershy on 7/8/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var model: WebViewModel

    var body: some View {
        WebView(model: model)
            .frame(minWidth: 800, minHeight: 600)
            .background(WindowGrabber())
            .navigationTitle(model.pageTitle)
    }
}
