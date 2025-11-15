//
//  Messages.swift
//  OldOS
//
//  Improved by ttoff999 – 11/15/25
//

import SwiftUI
import Foundation
import SQLite3
import UIKit

// MARK: - MODELS

struct SMSConversation: Identifiable {
    var id: Int
    var handle: String
    var lastMessage: String
    var lastDate: Date
}

struct SMSMessage: Identifiable {
    var id: Int
    var text: String?
    var isFromMe: Bool
    var date: Date
    var attachmentPath: String?
}

// MARK: - DATABASE

class SMSDatabase {
    static let shared = SMSDatabase()
    private var db: OpaquePointer?

    private init() {
        openDatabase()
    }

    private func dbPath() -> String {
        return "/var/mobile/Library/SMS/sms.db"
    }

    private func openDatabase() {
        if sqlite3_open(dbPath(), &db) != SQLITE_OK {
            print("ERREUR ouverture DB")
        }
    }

    // MARK: - get conversations

    func fetchConversations() -> [SMSConversation] {
        let q = """
        SELECT chat.ROWID, handle.id, message.text, message.date
        FROM chat
        JOIN chat_handle_join ON chat_handle_join.chat_id = chat.ROWID
        JOIN handle ON handle.ROWID = chat_handle_join.handle_id
        JOIN chat_message_join ON chat_message_join.chat_id = chat.ROWID
        JOIN message ON message.ROWID = chat_message_join.message_id
        GROUP BY chat.ROWID
        ORDER BY message.date DESC;
        """

        var stmt: OpaquePointer?
        var arr: [SMSConversation] = []

        if sqlite3_prepare_v2(db, q, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {

                let id = Int(sqlite3_column_int(stmt, 0))
                let handleC = sqlite3_column_text(stmt, 1)
                let msgC = sqlite3_column_text(stmt, 2)
                let dateI = sqlite3_column_int(stmt, 3)

                let handle = handleC != nil ? String(cString: handleC!) : "?"
                let msg = msgC != nil ? String(cString: msgC!) : ""
                let date = Date(timeIntervalSince1970: TimeInterval(dateI))

                arr.append(SMSConversation(id: id, handle: handle, lastMessage: msg, lastDate: date))
            }
        }

        sqlite3_finalize(stmt)
        return arr
    }

    // MARK: - get messages

    func fetchMessages(forChat id: Int) -> [SMSMessage] {

        let q = """
        SELECT message.ROWID, message.text, message.is_from_me, message.date, attachment.filename
        FROM chat_message_join
        JOIN message ON message.ROWID = chat_message_join.message_id
        LEFT JOIN attachment ON attachment.message_id = message.ROWID
        WHERE chat_message_join.chat_id = \(id)
        ORDER BY message.date ASC;
        """

        var stmt: OpaquePointer?
        var arr: [SMSMessage] = []

        if sqlite3_prepare_v2(db, q, -1, &stmt, nil) == SQLITE_OK {

            while sqlite3_step(stmt) == SQLITE_ROW {

                let mid = Int(sqlite3_column_int(stmt, 0))
                let textC = sqlite3_column_text(stmt, 1)
                let from = sqlite3_column_int(stmt, 2) == 1
                let dateI = sqlite3_column_int(stmt, 3)
                let attachC = sqlite3_column_text(stmt, 4)

                let text = textC != nil ? String(cString: textC!) : nil
                let date = Date(timeIntervalSince1970: TimeInterval(dateI))

                var attach: String?
                if let a = attachC {
                    let file = String(cString: a)
                    attach = "/var/mobile/Library/SMS/Attachments/\(file)"
                }

                arr.append(
                    SMSMessage(id: mid, text: text, isFromMe: from, date: date, attachmentPath: attach)
                )
            }
        }

        sqlite3_finalize(stmt)
        return arr
    }
}

// MARK: - LIST VIEW (iOS 6 style)

struct MessagesListView: View {
    @State var conversations: [SMSConversation] = []
    @State var selectedChat: SMSConversation?

    var body: some View {
        NavigationView {
            List(conversations) { c in
                NavigationLink(destination: ChatView(chat: c)) {
                    HStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 40)
                            .overlay(Text(String(c.handle.prefix(1))).font(.headline))

                        VStack(alignment: .leading) {
                            Text(c.handle)
                                .font(.system(size: 18, weight: .bold))

                            Text(c.lastMessage)
                                .lineLimit(1)
                                .foregroundColor(.gray)
                                .font(.system(size: 15))
                        }

                        Spacer()

                        Text(shortDate(c.lastDate))
                            .foregroundColor(.gray)
                            .font(.system(size: 13))
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationBarTitle("Messages", displayMode: .inline)
            .onAppear {
                conversations = SMSDatabase.shared.fetchConversations()
            }
        }
    }

    func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM"
        return f.string(from: d)
    }
}

// MARK: - CHAT VIEW

struct ChatView: View {
    var chat: SMSConversation

    @State var messages: [SMSMessage] = []
    @State var newMessage = ""

    var body: some View {
        VStack(spacing:0) {

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {

                        ForEach(messages) { msg in
                            HStack {
                                if msg.isFromMe == false { Spacer() }

                                VStack(alignment: msg.isFromMe ? .trailing : .leading) {
                                    
                                    if let path = msg.attachmentPath,
                                       let img = UIImage(contentsOfFile: path) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: 220)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .padding(msg.isFromMe ? .leading : .trailing, 50)
                                    }

                                    if let t = msg.text {
                                        Text(t)
                                            .padding(10)
                                            .background(
                                                msg.isFromMe ?
                                                    Color(red: 0.20, green: 0.52, blue: 1.0) :
                                                    Color(red: 210/255, green: 210/255, blue: 210/255)
                                            )
                                            .foregroundColor(msg.isFromMe ? .white : .black)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                            .shadow(color: .black.opacity(0.15), radius: 2)
                                            .padding(msg.isFromMe ? .leading : .trailing, 50)
                                    }
                                }

                                if msg.isFromMe == true { Spacer() }
                            }
                        }
                    }
                    .padding()
                }
                .onAppear {
                    messages = SMSDatabase.shared.fetchMessages(forChat: chat.id)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id) }
                        }
                    }
                }
            }

            // input bar
            inputBar
        }
        .navigationBarTitle(chat.handle, displayMode: .inline)
    }

    // MARK: - Input bar iOS 6

    var inputBar: some View {
        HStack {
            TextField("Message", text: $newMessage)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(8)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )

            Button(action: sendMessage) {
                Text("Envoyer")
                    .padding(8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(red: 230/255, green: 230/255, blue: 230/255))
        .shadow(radius: 2)
    }

    func sendMessage() {
        guard newMessage.count > 0 else { return }

        let fake = SMSMessage(
            id: Int.random(in: 999999...99999999),
            text: newMessage,
            isFromMe: true,
            date: Date(),
            attachmentPath: nil
        )

        messages.append(fake)
        newMessage = ""
    }
}

// MARK: - ENTRY POINT

struct MessagesIOS6: View {
    var body: some View {
        MessagesListView()
    }
}

struct MessagesIOS6_Previews: PreviewProvider {
    static var previews: some View {
        MessagesIOS6()
    }
}