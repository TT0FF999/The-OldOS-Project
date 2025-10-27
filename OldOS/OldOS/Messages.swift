//
//  Messages.swift
//  OldOS
//
//  Created by Zane Kleinberg on 5/24/21. To modify 10/27/25 by ttoff999
//

//Messages, Calendar, Youtube, and Mail are all coming soon. I have my own private version of these which I am currently working on, but decided to include the public version here.

import SwiftUI

struct Messages: View {
    @State var current_nav_view: String = "Main"
    @State var forward_or_backward: Bool = false 
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing:0) {
                    status_bar_in_app().frame(minHeight: 24, maxHeight:24).zIndex(1)
                    messages_title_bar(title: "Messages").frame(minWidth: geometry.size.width, maxWidth: geometry.size.width, minHeight: 60, maxHeight:60).zIndex(1)
                    VStack {
                    ForEach(0..<Int(geometry.size.height/80)) {_ in
                        Spacer()
                        Rectangle().fill(Color(red: 224/255, green: 224/255, blue: 224/255)).frame(height: 1)
                    }
                    }
                }
            }.background(Color.white).compositingGroup().clipped()
        }
    }
}

struct messages_title_bar : View {
    var title:String
    public var done_action: (() -> Void)?
    var show_done: Bool?
    var body :some View {
        ZStack {
            LinearGradient(gradient: Gradient(stops: [.init(color:Color(red: 180/255, green: 191/255, blue: 205/255), location: 0.0), .init(color:Color(red: 136/255, green: 155/255, blue: 179/255), location: 0.49), .init(color:Color(red: 128/255, green: 149/255, blue: 175/255), location: 0.49), .init(color:Color(red: 110/255, green: 133/255, blue: 162/255), location: 1.0)]), startPoint: .top, endPoint: .bottom).border_bottom(width: 1, edges: [.bottom], color: Color(red: 45/255, green: 48/255, blue: 51/255)).innerShadowBottom(color: Color(red: 230/255, green: 230/255, blue: 230/255), radius: 0.025)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(title).ps_innerShadow(Color.white, radius: 0, offset: 1, angle: 180.degrees, intensity: 0.07).font(.custom("Helvetica Neue Bold", fixedSize: 22)).shadow(color: Color.black.opacity(0.21), radius: 0, x: 0.0, y: -1).id(title)
                    Spacer()
                }
                Spacer()
            }
            HStack {
                Spacer()
                tool_bar_rectangle_button_larger_image(action: {done_action?()}, button_type: .blue_gray, content: "compose", use_image: true).padding(.trailing, 5)
            }
            
        }
    }
}


struct Messages_Previews: PreviewProvider {
    static var previews: some View {
        Messages()
    }
}
