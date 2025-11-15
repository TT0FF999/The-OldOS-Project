//
//  Messages.swift
//  OldOS
//
//  Improved by ttoff999 – 11/15/25
//

import SwiftUI
import SQLite3
import Foundation

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
    let handle: String?
}


// ---------------------------
// MARK: - SQLite Reader
// ---------------------------

final class SQLiteSMS {
    private var db: OpaquePointer? = nil
    private(set) var dbPath: String
    
    // MARK: init
    init?(bundleDBName: String = "sms") {
        guard let url = Bundle.main.url(forResource: bundleDBName, withExtension: "db") else {
            print("❌ sms.db introuvable")
            return nil
        }
        dbPath = url.path
        
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("❌ Impossible d’ouvrir la DB")
            db = nil
            return nil
        }
    }
    
    deinit { sqlite3_close(db) }
    
    // MARK: timestamp normalisation
    private func normalizeTimestamp(_ raw: Int64) -> Date {
        let now = Date().timeIntervalSince1970
        var seconds = Double(raw)
        
        switch raw {
            case 1_000_000_000_000...9_000_000_000_000:
                seconds /= 1000.0
            case 10_000_000_000_000...:
                seconds /= 1_000_000.0
            default: break
        }
        
        var date = Date(timeIntervalSince1970: seconds)
        
        // Correction si timestamp Cocoa (depuis 2001)
        if date.timeIntervalSince1970 > now + 31536000 || date.timeIntervalSince1970 < 946684800 {
            date = Date(timeIntervalSince1970: seconds - 978307200)
        }
        return date
    }
    
    // MARK: fetch Conversations
    func fetchConversations(limit: Int = 200) -> [Conversation] {
        var results: [Conversation] = []
        
        let sql = """
        SELECT
          chat.ROWID,
          chat.display_name,
          (SELECT message.text FROM message
             JOIN chat_message_join cmj ON cmj.message_id = message.ROWID
             WHERE cmj.chat_id = chat.ROWID
             ORDER BY message.date DESC LIMIT 1),
          (SELECT message.date FROM message
             JOIN chat_message_join cmj ON cmj.message_id = message.ROWID
             WHERE cmj.chat_id = chat.ROWID
             ORDER BY message.date DESC LIMIT 1)
        FROM chat
        ORDER BY last_date DESC
        LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let display = stmt.stringCol(1)
            let lastText = stmt.stringCol(2)
            
            var dateObj: Date? = nil
            if stmt.hasValue(3) {
                let raw = sqlite3_column_int64(stmt, 3)
                dateObj = normalizeTimestamp(raw)
            }
            
            results.append(Conversation(
                id: id,
                displayName: display,
                lastMessageText: lastText,
                lastMessageDate: dateObj
            ))
        }
        sqlite3_finalize(stmt)
        return results
    }
    
    // MARK: fetch messages
    func fetchMessages(forChatId chatId: Int64) -> [MessageModel] {
        var results: [MessageModel] = []
        
        let sql = """
        SELECT message.ROWID,
               message.text,
               message.date,
               message.is_from_me,
               COALESCE(handle.id, '')
        FROM message
        JOIN chat_message_join cmj ON cmj.message_id = message.ROWID
        LEFT JOIN handle ON message.handle_id = handle.ROWID
        WHERE cmj.chat_id = ?
        ORDER BY message.date ASC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        
        sqlite3_bind_int64(stmt, 1, chatId)
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let text = stmt.stringCol(1)
            let handle = stmt.stringCol(4)
            
            let date = stmt.hasValue(2) ? normalizeTimestamp(sqlite3_column_int64(stmt, 2)) : nil
            let isFromMe = sqlite3_column_int(stmt, 3) != 0
            
            results.append(MessageModel(
                id: id, text: text, date: date,
                isFromMe: isFromMe, handle: handle
            ))
        }
        sqlite3_finalize(stmt)
        return results
    }
}


// ---------------------------
// MARK: - SQLite helpers
// ---------------------------

private extension OpaquePointer {
    func stringCol(_ idx: Int32) -> String? {
        guard sqlite3_column_type(self, idx) != SQLITE_NULL,
              let c = sqlite3_column_text(self, idx) else { return nil }
        return String(cString: c)
    }
    
    func hasValue(_ idx: Int32) -> Bool {
        sqlite3_column_type(self, idx) != SQLITE_NULL
    }
}


// ---------------------------
// MARK: - Formatters (optimisé)
// ---------------------------

fileprivate let shortFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f
}()

fileprivate let longFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()


// ---------------------------
// MARK: - UI Components
// ---------------------------

struct ConversationRow: View {
    let convo: Conversation
    
    var body: some View {
        HStack(spacing:12) {
            Circle()
                .frame(width:44, height:44)
                .overlay(Text(initials(from: convo.displayName)).bold())
                .opacity(0.12)
            
            VStack(alignment:.leading) {
                HStack {
                    Text(convo.displayName ?? "Unknown")
                        .font(.system(size:16, weight:.semibold))
                    Spacer()
                    if let d = convo.lastMessageDate {
                        Text(shortFormatter.string(from: d))
                            .foregroundColor(.gray)
                            .font(.system(size:12))
                    }
                }
                Text(convo.lastMessageText ?? "")
                    .font(.system(size:14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical,8)
    }
    
    private func initials(from s: String?) -> String {
        guard let s = s else { return "?" }
        let parts = s.split(separator: " ")
        if parts.count > 1 { return "\(parts[0].first!)\(parts[1].first!)".uppercased() }
        return String(s.prefix(1)).uppercased()
    }
}

struct MessageBubble: View {
    let message: MessageModel
    
    var body: some View {
        HStack {
            if message.isFromMe { Spacer() }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text ?? "[Pièce jointe]")
                    .padding(10)
                    .background(message.isFromMe ? Color.blue : Color.gray.opacity(0.15))
                    .foregroundColor(message.isFromMe ? .white : .primary)
                    .cornerRadius(16)
                
                if let d = message.date {
                    Text(longFormatter.string(from: d))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: 320, alignment: message.isFromMe ? .trailing : .leading)
            
            if !message.isFromMe { Spacer() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}


// ---------------------------
// MARK: - Main Messages UI
// ---------------------------

struct Messages: View {
    
    @State private var conversations: [Conversation] = []
    @State private var selectedChatId: Int64? = nil
    @State private var messagesInChat: [MessageModel] = []
    @State private var smsReader: SQLiteSMS? = nil
    @State private var current_nav_view: String = "Main"
    
    var body: some View {
        
        GeometryReader { geo in
            VStack(spacing: 0) {
                
                status_bar_in_app()
                    .frame(height: 24)
                
                messages_title_bar(title: "Messages")
                    .frame(height: 60)
                
                Divider()
                
                HStack(spacing:0) {
                    
                    // CONVERSATIONS LIST
                    List(conversations) { c in
                        Button {
                            openChat(c.id)
                        } label {
                            ConversationRow(convo: c)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: geo.size.width * 0.36)
                    
                    Divider()
                    
                    // CHAT VIEW
                    Group {
                        if current_nav_view == "Main" {
                            VStack {
                                Spacer()
                                Text("Sélectionne une conversation")
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                        } else {
                            chatView
                        }
                    }
                    .frame(width: geo.size.width * 0.64)
                }
            }
            .background(Color.white)
            .onAppear(perform: loadConversations)
        }
    }
    
    
    // MARK: Chat Loading
    private func loadConversations() {
        smsReader = SQLiteSMS()
        if let r = smsReader {
            conversations = r.fetchConversations()
        }
    }
    
    private func openChat(_ id: Int64) {
        selectedChatId = id
        withAnimation { current_nav_view = "Chat" }
        loadMessages(chatId: id)
    }
    
    private func loadMessages(chatId: Int64) {
        Task.detached {
            guard let r = smsReader else { return }
            let fetched = r.fetchMessages(forChatId: chatId)
            
            await MainActor.run {
                withAnimation {
                    messagesInChat = fetched
                }
            }
        }
    }
    
    
    // MARK: Chat view
    private var chatView: some View {
        
        VStack(spacing: 0) {
            
            HStack {
                Button {
                    withAnimation { current_nav_view = "Main" }
                } label {
                    Image(systemName: "chevron.left")
                }
                .padding()
                
                Text("Conversation")
                    .font(.headline)
                
                Spacer()
            }
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack {
                        ForEach(messagesInChat) { msg in
                            MessageBubble(message: msg).id(msg.id)
                        }
                    }
                }
                .onChange(of: messagesInChat.count) { _ in
                    scrollToBottom(proxy)
                }
                .onAppear {
                    scrollToBottom(proxy)
                }
            }
        }
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = messagesInChat.last {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}