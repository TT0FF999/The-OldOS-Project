//
//  Messages.swift
//  OldOS
//
//  Created by Zane Kleinberg on 5/24/21. To modify 10/27/25 by ttoff999
//

//Messages, Calendar, Youtube, and Mail are all coming soon. I have my own private version of these which I am currently working on, but decided to include the public version here.

import SwiftUI
import SQLite3
import Foundation

struct Messages: View {
    @State var current_nav_view: String = "Main"
    @State var forward_or_backward: Bool = false 
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing:0) {
                    status_bar_in_app().frame(minHeight: 24, maxHeight:24).zIndex(1)
                    messages_title_bar(title: "Messages").frame(minWidth: geometry.size.width, maxWidth: geometry.size.width, minHeight: 60, maxHeight:60).zIndex(1)
                    // *** Add the code 
                    VStack {
                    ForEach(0..<Int(geometry.size.height/80)) {_ in
                        Spacer()
                        Rectangle().fill(Color(red: 224/255, green: 224/255, blue: 224/255)).frame(height: 1)
                    }
                }
                // *** End of the app code 
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
// ---------------------------
// MARK: - Models
// ---------------------------
struct Conversation: Identifiable {
    let id: Int64
    var displayName: String?
    var lastMessageText: String?
    var lastMessageDate: Date?
}

struct MessageModel: Identifiable {
    let id: Int64
    let text: String?
    let date: Date?
    let isFromMe: Bool
    let handle: String? // phone/email
}

// ---------------------------
// MARK: - SQLiteSMS (reader)
// ---------------------------
final class SQLiteSMS {
    private var db: OpaquePointer? = nil
    private(set) var dbPath: String
    
    init?(bundleDBName: String = "sms") {
        // Find sms.db in bundle
        guard let url = Bundle.main.url(forResource: bundleDBName, withExtension: "db") else {
            print("sms.db introuvable dans le bundle")
            return nil
        }
        dbPath = url.path
        
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("Impossible d'ouvrir la DB: \(dbPath)")
            db = nil
            return nil
        }
    }
    
    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
    
    // Heuristic pour convertir les timestamps troublants dans sms.db
    // La DB peut contenir: secondes unix, millisecondes, microsecondes, ou secondes depuis 2001-01-01
    private func normalizeTimestamp(_ raw: Int64) -> Date {
        let now = Date().timeIntervalSince1970
        var candidateSeconds = Double(raw)
        
        // heuristics
        if raw > 1_000_000_000_000_000_000 { // improbable
            candidateSeconds = Double(raw) / 1_000_000_000.0
        } else if raw > 1_000_000_000_000 { // > 1e12 => micro/nano scale
            candidateSeconds = Double(raw) / 1_000_000.0
            if candidateSeconds > now + 60*60*24*365 { // still too large -> try /1e9
                candidateSeconds = Double(raw) / 1_000_000_000.0
            }
        } else if raw > 1_000_000_000 { // >1e9 maybe milliseconds
            candidateSeconds = Double(raw) / 1000.0
        } else {
            candidateSeconds = Double(raw)
        }
        
        var date = Date(timeIntervalSince1970: candidateSeconds)
        
        // Some records are seconds since 2001-01-01 (Cocoa reference date)
        // If date is obviously in future or before 2000, attempt subtraction of 978307200
        if date.timeIntervalSince1970 > now + (60*60*24*365) || date.timeIntervalSince1970 < 946684800 { // before 2000
            // try reference date
            let alt = Date(timeIntervalSince1970: candidateSeconds - 978307200)
            if alt.timeIntervalSince1970 <= now + (60*60*24*365) && alt.timeIntervalSince1970 > 946684800 {
                date = alt
            }
        }
        return date
    }
    
    // Fetch conversations (basic)
    func fetchConversations(limit: Int = 200) -> [Conversation] {
        var results: [Conversation] = []
        // Query: get chat rowid and display name + last message (works on common sms.db schemas)
        let sql =
        """
        SELECT
          chat.ROWID as chat_id,
          chat.display_name,
          (SELECT message.text FROM message
             JOIN chat_message_join cmj ON cmj.message_id = message.ROWID
             WHERE cmj.chat_id = chat.ROWID
             ORDER BY message.date DESC LIMIT 1) as last_text,
          (SELECT message.date FROM message
             JOIN chat_message_join cmj ON cmj.message_id = message.ROWID
             WHERE cmj.chat_id = chat.ROWID
             ORDER BY message.date DESC LIMIT 1) as last_date
        FROM chat
        ORDER BY last_date DESC
        LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("prepare fetchConversations failed")
            return []
        }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chatId = sqlite3_column_int64(stmt, 0)
            var displayName: String? = nil
            if let cstr = sqlite3_column_text(stmt, 1) {
                displayName = String(cString: cstr)
            }
            var lastText: String? = nil
            if let cstr = sqlite3_column_text(stmt, 2) {
                lastText = String(cString: cstr)
            }
            var dateObj: Date? = nil
            if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                let raw = sqlite3_column_int64(stmt, 3)
                dateObj = normalizeTimestamp(raw)
            }
            results.append(Conversation(id: chatId, displayName: displayName, lastMessageText: lastText, lastMessageDate: dateObj))
        }
        sqlite3_finalize(stmt)
        return results
    }
    
    // Fetch messages for a conversation/chat id
    func fetchMessages(forChatId chatId: Int64) -> [MessageModel] {
        var results: [MessageModel] = []
        // Note: "is_from_me" can be named "is_from_me" or "is_from_me" stored as integer.
        // We also attempt to get handle (sender) from handle table if present.
        let sql =
        """
        SELECT message.ROWID as msgid,
               message.text,
               message.date,
               message.is_from_me,
               COALESCE(handle.id, '') as handle_id
        FROM message
        JOIN chat_message_join cmj ON cmj.message_id = message.ROWID
        LEFT JOIN handle ON message.handle_id = handle.ROWID
        WHERE cmj.chat_id = ?
        ORDER BY message.date ASC, message.ROWID ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("prepare fetchMessages failed")
            return []
        }
        sqlite3_bind_int64(stmt, 1, chatId)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let msgId = sqlite3_column_int64(stmt, 0)
            var text: String? = nil
            if let cstr = sqlite3_column_text(stmt, 1) {
                text = String(cString: cstr)
            }
            var dateObj: Date? = nil
            if sqlite3_column_type(stmt, 2) != SQLITE_NULL {
                let raw = sqlite3_column_int64(stmt, 2)
                dateObj = normalizeTimestamp(raw)
            }
            var isFromMe = false
            if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                let val = sqlite3_column_int(stmt, 3)
                isFromMe = (val != 0)
            }
            var handle: String? = nil
            if let cstr = sqlite3_column_text(stmt, 4) {
                let s = String(cString: cstr)
                if !s.isEmpty { handle = s }
            }
            results.append(MessageModel(id: msgId, text: text, date: dateObj, isFromMe: isFromMe, handle: handle))
        }
        sqlite3_finalize(stmt)
        return results
    }
    
    // Optional: find chat id by handle (phone/email) or displayName
    func chatId(forHandle handle: String) -> Int64? {
        let sql = """
        SELECT chat.ROWID FROM chat
        JOIN chat_handle_join chj ON chj.chat_id = chat.ROWID
        JOIN handle h ON h.ROWID = chj.handle_id
        WHERE h.id = ?
        LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, (handle as NSString).utf8String, -1, nil)
        var result: Int64? = nil
        if sqlite3_step(stmt) == SQLITE_ROW {
            result = sqlite3_column_int64(stmt, 0)
        }
        sqlite3_finalize(stmt)
        return result
    }
}

// ---------------------------
// MARK: - Views
// ---------------------------

struct ConversationRow: View {
    let convo: Conversation
    var body: some View {
        HStack(spacing:12) {
            // placeholder avatar
            Circle().frame(width:44, height:44).overlay(Text(initials(from: convo.displayName)).bold()).opacity(0.12)
            VStack(alignment:.leading) {
                HStack {
                    Text(convo.displayName ?? "Unknown").font(.system(size:16, weight:.semibold))
                    Spacer()
                    if let d = convo.lastMessageDate {
                        Text(shortTimeString(from: d)).font(.system(size:12)).foregroundColor(.gray)
                    }
                }
                Text(convo.lastMessageText ?? "").font(.system(size:14)).foregroundColor(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical,8)
    }
    private func initials(from s: String?) -> String {
        guard let s = s, !s.isEmpty else { return "?" }
        let parts = s.split(separator: " ")
        if parts.count == 1 { return String(parts[0].prefix(1)).uppercased() }
        return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
    }
    private func shortTimeString(from d: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        return fmt.string(from: d)
    }
}

struct MessageBubble: View {
    let message: MessageModel
    var body: some View {
        HStack {
            if message.isFromMe { Spacer() }
            VStack(alignment: .leading, spacing: 4) {
                if let txt = message.text {
                    Text(txt).padding(10).fixedSize(horizontal: false, vertical: true)
                        .background(message.isFromMe ? Color.blue : Color.gray.opacity(0.15))
                        .foregroundColor(message.isFromMe ? Color.white : Color.primary)
                        .cornerRadius(16)
                } else {
                    // placeholder for attachments
                    Text("[Pièce jointe]").italic().padding(10)
                        .background(message.isFromMe ? Color.blue : Color.gray.opacity(0.15))
                        .foregroundColor(message.isFromMe ? Color.white : Color.primary)
                        .cornerRadius(12)
                }
                if let d = message.date {
                    Text(longTimeString(from: d)).font(.caption2).foregroundColor(.gray)
                }
            }.frame(maxWidth: 320, alignment: message.isFromMe ? .trailing : .leading)
            if !message.isFromMe { Spacer() }
        }.padding(.horizontal, 10).padding(.vertical, 4)
    }
    private func longTimeString(from d: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: d)
    }
}

// ---------------------------
// MARK: - Main Messages View (List + Conversation)
// ---------------------------
struct Messages: View {
    @State var current_nav_view: String = "Main"
    @State var forward_or_backward: Bool = false
    @State private var conversations: [Conversation] = []
    @State private var selectedChatId: Int64? = nil
    @State private var messagesInChat: [MessageModel] = []
    @State private var smsReader: SQLiteSMS? = nil
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing:0) {
                    status_bar_in_app().frame(minHeight: 24, maxHeight:24).zIndex(1)
                    messages_title_bar(title: "Messages").frame(minWidth: geometry.size.width, maxWidth: geometry.size.width, minHeight: 60, maxHeight:60).zIndex(1)
                    
                    Divider()
                    
                    HStack {
                        // Left: Conversations list
                        VStack {
                            List(conversations) { c in
                                Button(action: {
                                    self.selectedChatId = c.id
                                    loadMessages(chatId: c.id)
                                    withAnimation { self.current_nav_view = "Chat" }
                                }) {
                                    ConversationRow(convo: c)
                                }.buttonStyle(PlainButtonStyle())
                            }
                        }.frame(width: geometry.size.width * 0.36)
                        
                        Divider()
                        
                        // Right: Chat view
                        VStack {
                            if current_nav_view == "Main" {
                                VStack {
                                    Spacer()
                                    Text("Sélectionne une conversation").foregroundColor(.gray)
                                    Spacer()
                                }
                            } else if current_nav_view == "Chat" {
                                VStack(spacing:0) {
                                    HStack {
                                        Button(action: {
                                            withAnimation { self.current_nav_view = "Main" }
                                        }) {
                                            Image(systemName: "chevron.left")
                                        }.padding()
                                        Text("Conversation").font(.headline)
                                        Spacer()
                                    }
                                    Divider()
                                    ScrollViewReader { proxy in
                                        ScrollView {
                                            LazyVStack {
                                                ForEach(messagesInChat) { msg in
                                                    MessageBubble(message: msg).id(msg.id)
                                                }
                                            }.padding(.top, 8)
                                        }
                                        .onChange(of: messagesInChat.count) { _ in
                                            // scroll to bottom
                                            if let last = messagesInChat.last {
                                                proxy.scrollTo(last.id, anchor: .bottom)
                                            }
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }.frame(minWidth: geometry.size.width * 0.64)
                    }
                    .onAppear {
                        // init reader
                        if smsReader == nil {
                            smsReader = SQLiteSMS(bundleDBName: "sms")
                            if let r = smsReader {
                                self.conversations = r.fetchConversations()
                            } else {
                                print("Impossible d'initialiser SQLiteSMS")
                            }
                        }
                    }
                }
                .background(Color.white)
                .compositingGroup()
                .clipped()
            }
        }
    }
    
    // load messages for chat id
    private func loadMessages(chatId: Int64) {
        guard let r = smsReader else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let fetched = r.fetchMessages(forChatId: chatId)
            DispatchQueue.main.async {
                withAnimation {
                    self.messagesInChat = fetched
                }
            }
        }
    }
}

// Preview (optionnel)
struct Messages_Previews: PreviewProvider {
    static var previews: some View {
        Messages()
    }
}