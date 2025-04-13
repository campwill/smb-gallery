//
//  ContentView.swift
//  SMBGallery
//
//  Created by William Campbell on 4/12/25.
//

import SwiftUI
import Security

// structure used for each smb connection
struct Server: Identifiable, Codable {
    var id = UUID() // unique id used for each server
    var serverName: String
    var ipAddress: String
    var shareName: String
    var username: String
    // server password stored in keychain
}

// generate a unique pair for a server connection
func makeKeychainKey(username: String, ip: String) -> String {
    return "\(username)@\(ip)"
}

// keychain helper class for storing, retrieving, and deleting server passwords
class KeychainHelper {
    static func savePassword(password: String, account: String) {
        let passwordData = password.data(using: .utf8)!
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account,
                                    kSecValueData as String: passwordData]
        
        // delete any existing password for the account
        SecItemDelete(query as CFDictionary)
        
        // add password to keychain
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            print("Password saved successfully for account: \(account)")
        } else {
            print("Error saving password for account: \(status)")
        }
    }

    static func loadPassword(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: kCFBooleanTrue!,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        
        // retrieve password from keychain
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data, let password = String(data: data, encoding: .utf8) {
            print("Password loaded successfully for account: \(account)")
            return password
        } else {
            print("Error loading password for account: \(status)")
            return nil
        }
    }

    static func deletePassword(account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account]
        
        // delete password from keychain
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            print("Password deleted successfully for account: \(account)")
        } else {
            print("Error deleting password for account: \(status)")
        }
    }
}

class ServerDataManager {
    // save server information to UserDefaults (without password)
    static func saveServers(servers: [Server]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(servers) {
            UserDefaults.standard.set(encoded, forKey: "servers")
            print("Servers saved to UserDefaults.")
        }
    }
    
    // load server information from UserDefaults
    static func loadServers() -> [Server] {
        if let savedServersData = UserDefaults.standard.data(forKey: "servers") {
            let decoder = JSONDecoder()
            if let decodedServers = try? decoder.decode([Server].self, from: savedServersData) {
                print("Servers loaded from UserDefaults.")
                return decodedServers
            }
        }
        return []
    }
}

struct ContentView: View {
    @State private var servers: [Server] = ServerDataManager.loadServers()
    @State private var newServerName: String = ""
    @State private var newServerIP: String = ""
    @State private var newShareName: String = ""
    @State private var newServerUsername: String = ""
    @State private var newServerPassword: String = ""
    @State private var isAddingServer = false // used to display modal sheet
    
    func addServer() {
        // save new server's password to keychain
        KeychainHelper.savePassword(password: newServerPassword, account: makeKeychainKey(username: newServerUsername, ip: newServerIP))

        // create a new server
        let newServer = Server(
            serverName: newServerName,
            ipAddress: newServerIP,
            shareName: newShareName,
            username: newServerUsername
        )

        // add new server to server list
        servers.append(newServer)
        
        // save updated server list to UserDefaults
        ServerDataManager.saveServers(servers: servers)

        // clear and dismiss form
        newServerName = ""
        newServerIP = ""
        newShareName = ""
        newServerUsername = ""
        newServerPassword = ""
        isAddingServer = false
    }

    func deleteServer(at offsets: IndexSet) {
        let serverToDelete = servers[offsets.first!]
        
        // delete server's password from keychain
        KeychainHelper.deletePassword(account: makeKeychainKey(username: serverToDelete.username, ip: serverToDelete.ipAddress))
        
        // remove server from server list
        servers.remove(atOffsets: offsets)
        
        // save updated server list to UserDefaults
        ServerDataManager.saveServers(servers: servers)
    }
    
    // check if add server form is complete
    func isComplete() -> Bool {
        return !newServerName.isEmpty && !newShareName.isEmpty && !newServerIP.isEmpty && !newServerUsername.isEmpty && !newServerPassword.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // default message
                if servers.isEmpty {
                    Text("Add a server to get started.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding()
                }
                
                // display each saved server in list
                List {
                    ForEach(servers) { server in
                        // if clicked go to ServerDetailView (see ServerDetailView.swift)
                        NavigationLink(destination: ServerDetailView(server: server)) {
                            VStack(alignment: .leading) {
                                Text("\(server.serverName)")
                                Text("IP: \(server.ipAddress)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding()
                    }
                    .onDelete(perform: deleteServer)
                }
            }
            
            .navigationBarTitle("Server List", displayMode: .inline)
            
            // add server button used to enable modal sheet for collecting server information
            .navigationBarItems(
                trailing: Button(action: {
                    isAddingServer.toggle()
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(.blue)
                }
            )
            
            // modal sheet used to collect server information
            .sheet(isPresented: $isAddingServer) {
                NavigationStack {
                    Form {
                        TextField("Server Name", text: $newServerName)
                            .autocapitalization(.none)
                        Section(header: Text("Server Details")) {
                            TextField("IP Address", text: $newServerIP)
                                .keyboardType(.decimalPad)
                            TextField("Share Name", text: $newShareName)
                                .autocapitalization(.none)
                        }
                        Section(header: Text("Server Details")) {
                            TextField("Username", text: $newServerUsername)
                                .autocapitalization(.none)
                            SecureField("Password", text: $newServerPassword)
                                .autocapitalization(.none)
                        }
                    }
                    
                    .navigationBarTitle("Add New Server", displayMode: .inline)
                    
                    .navigationBarItems(
                        // cancel button clears and dissmisses form
                        leading: Button("Cancel") {
                            isAddingServer = false
                            newServerName = ""
                            newServerIP = ""
                            newShareName = ""
                            newServerUsername = ""
                            newServerPassword = ""
                        },
                        
                        // add button is only enabled if the form is complete
                        trailing: Button("Add") {
                            addServer()
                        }
                        .disabled(!isComplete())
                    )
                }
            }
        }
    }
}
