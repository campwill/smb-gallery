//
//  ServerDetailView.swift
//  SMBGallery
//
//  Created by William Campbell on 4/12/25.
//

import SwiftUI
import SMBClient

struct ServerDetailView: View {
    let server: Server
    @Environment(\.presentationMode) var presentationMode // presentation mode used to display errors
    @State private var files: [File] = [] // list of all files in a directory
    @State private var imageFiles: [File] = [] // list of all image files in a directory
    @State private var selectedTab = "File View" // used to specify selected view (file view or gallery view)
    @State private var showErrorAlert = false // used to display errors
    @State private var imageThumbnails: [String: UIImage] = [:] // used to store image files for thumbnails
    @State private var smbClient: SMBClient? // the SMB client for persistent connection
    @State private var currentPath = "" // tracks current directory path
    
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)] // grid layout
    
    var body: some View {
        NavigationStack {
            VStack {
                if selectedTab == "File View" {
                    // display files in file view
                    List {
                        ForEach(files, id: \.self) { file in
                            if file.name != "." {
                                Button(action: {
                                    handleFileTap(file)
                                }) {
                                    Text(file.name)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } else {
                    // display image files in gallery view
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(imageFiles, id: \.self) { file in
                                if let thumbnail = imageThumbnails[file.name] {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                } else {
                                    ProgressView()
                                        .frame(width: 100, height: 100)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            
            // connect to server on load
            .onAppear {
                connectToServer()
            }
            
            // picker to switch between file view and gallery view
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Spacer() // used align to the center
                        Picker("View Options", selection: $selectedTab) {
                            Text("File View").tag("File View")
                            Text("Gallery View").tag("Gallery View")
                        }
                        .pickerStyle(SegmentedPickerStyle()) // makes it look like a pill toggle
                        Spacer() // used align to the center
                    }
                }
            }
            
            // error alert
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text("Could not connect to server. Please check your credentials and try again."),
                    dismissButton: .default(Text("OK")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                )
            }
        }
    }

    private func connectToServer() {
        Task {
            do {
                // retrieve server password from keychain
                guard let password = KeychainHelper.loadPassword(account: makeKeychainKey(username: server.username, ip: server.ipAddress)) else {
                    throw NSError(domain: "Missing password", code: 1)
                }

                // connect to smb client
                let client = SMBClient(host: server.ipAddress)
                try await client.login(username: server.username, password: password)
                try await client.connectShare(server.shareName)
                smbClient = client

                // load root directory
                try await loadDirectory(path: "")
            } catch {
                DispatchQueue.main.async {
                    showErrorAlert = true
                }
            }
        }
    }

    // load directory contents based on the current path
    private func loadDirectory(path: String) async throws {
        guard let client = smbClient else { return }
        
        // obtain list of files from directory
        let directoryFiles = try await client.listDirectory(path: path)
        //print(directoryFiles)
        files = directoryFiles
        
        // filter for image files
        imageFiles = directoryFiles.filter { file in
            let lowercasedFileName = file.name.lowercased()
            return lowercasedFileName.hasSuffix(".jpg") || lowercasedFileName.hasSuffix(".jpeg") || lowercasedFileName.hasSuffix(".png")
        }
        
        // download thumbnails for image files
        for file in imageFiles {
            await fetchThumbnail(for: file)
        }
    }
    
    // download images to create thumbnails
    private func fetchThumbnail(for file: File) async {
        guard let client = smbClient else { return }
        
        do {
            //print(currentPath + file.name)
            let imageData = try await client.download(path: currentPath + "/" + file.name)
            if let thumbnail = UIImage(data: imageData) {
                DispatchQueue.main.async {
                    imageThumbnails[file.name] = thumbnail
                }
            }
        } catch {
            //print("Failed to download image: \(error)")
        }
    }

    // handle file tap (for navigating directories)
    private func handleFileTap(_ file: File) {
        if file.name == ".." && currentPath.isEmpty {
            return
        } else if file.name == ".." {
            // traverse to parent directory
            if let lastSlashIndex = currentPath.lastIndex(of: "/") {
                // remove the last directory from currentPath
                currentPath = String(currentPath[..<lastSlashIndex])
            } else {
                // if no slash exists, reset to root
                currentPath = ""
            }

            // load parent directory
            Task {
                do {
                    try await loadDirectory(path: currentPath)
                } catch {
                    DispatchQueue.main.async {
                        showErrorAlert = true
                    }
                }
            }
        } else if file.isDirectory {
            // traverse to new directory
            let newPath = currentPath.isEmpty ? file.name : currentPath + "/" + file.name
            
            // load new directory
            Task {
                do {
                    currentPath = newPath
                    try await loadDirectory(path: newPath)
                } catch {
                    DispatchQueue.main.async {
                        showErrorAlert = true
                    }
                }
            }
        } else {
            return
        }
    }
}

/*
// for Xcode preview
#Preview {
    // create a mock server object for the preview
    let testServer = Server(serverName: "Test Server", ipAddress: "192.168.1.1", shareName: "Public", username: "admin", password: "password" )
    
    // provide the mock server to the ServerDetailView
    ServerDetailView(server: testServer)
}
*/
