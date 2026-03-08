import Foundation

// Simple test to see what Wikipedia returns
func testWikipediaAPI() {
    print("=== Testing Wikipedia API ===")
    
    // Try different page titles
    let pageTitles = [
        "Ray of Light (Madonna album)",
        "Ray of Light",
        "Ray_of_Light_(Madonna_album)",
        "Madonna Ray of Light"
    ]
    
    for pageTitle in pageTitles {
        let encodedTitle = pageTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pageTitle
        let urlString = "https://en.wikipedia.org/w/api.php?action=parse&page=\(encodedTitle)&prop=wikitext&format=json&origin=*"
        
        guard let url = URL(string: urlString) else {
            print("Failed to create URL for: \(pageTitle)")
            continue
        }
        
        print("\n--- Testing: \(pageTitle) ---")
        print("URL: \(urlString)")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error: \(error)")
                semaphore.signal()
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                print("No data received")
                semaphore.signal()
                return
            }
            
            // Print raw response
            let rawString = String(data: data, encoding: .utf8)
            print("Response length: \(data.count) bytes")
            print("First 500 chars of response:")
            print(rawString?.prefix(500) ?? "No string")
            
            // Try to parse as JSON
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("\nParsed JSON keys: \(json.keys)")
                    if let parse = json["parse"] as? [String: Any] {
                        print("Parse keys: \(parse.keys)")
                        if let wikitextDict = parse["wikitext"] as? [String: Any] {
                            print("Wikitext keys: \(wikitextDict.keys)")
                            if let wikitext = wikitextDict["*"] as? String {
                                print("Wikitext length: \(wikitext.count) characters")
                                print("First 200 chars of wikitext:")
                                print(wikitext.prefix(200))
                            }
                        }
                    } else if let error = json["error"] as? [String: Any] {
                        print("Wikipedia API error: \(error)")
                    }
                }
            } catch {
                print("JSON parsing error: \(error)")
            }
            
            semaphore.signal()
        }
        
        task.resume()
        _ = semaphore.wait(timeout: .now() + 10)
    }
}

testWikipediaAPI()