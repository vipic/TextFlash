import Foundation

private final class TrieNode {
    var children: [Character: TrieNode] = [:]
    var expansion: String?
}

private final class Trie {
    let root = TrieNode()

    func insert(abbreviation: String, expansion: String) {
        var node = root
        for ch in abbreviation {
            if let next = node.children[ch] {
                node = next
            } else {
                let next = TrieNode()
                node.children[ch] = next
                node = next
            }
        }
        node.expansion = expansion
    }

    func search(_ prefix: String) -> (matched: Bool, expansion: String?) {
        var node = root
        for ch in prefix {
            guard let next = node.children[ch] else {
                return (false, nil)
            }
            node = next
        }
        return (true, node.expansion)
    }

    func remove(abbreviation: String) {
        var node = root
        var path: [(TrieNode, Character)] = []
        for ch in abbreviation {
            guard let next = node.children[ch] else { return }
            path.append((node, ch))
            node = next
        }
        node.expansion = nil

        for (parent, ch) in path.reversed() {
            guard let child = parent.children[ch], child.children.isEmpty, child.expansion == nil else {
                break
            }
            parent.children.removeValue(forKey: ch)
        }
    }

    func clear() {
        root.children.removeAll()
    }
}

struct SnippetMatch: Equatable {
    let abbreviation: String
    let expansion: String
}

final class SnippetMatcher {
    private let trie = Trie()

    func insert(abbreviation: String, expansion: String) {
        trie.insert(abbreviation: abbreviation, expansion: expansion)
    }

    func remove(abbreviation: String) {
        trie.remove(abbreviation: abbreviation)
    }

    func clear() {
        trie.clear()
    }

    func match(in buffer: String) -> SnippetMatch? {
        guard !buffer.isEmpty else { return nil }

        for i in buffer.indices {
            let suffix = String(buffer[i...])
            let (matched, expansion) = trie.search(suffix)
            if let text = expansion {
                return SnippetMatch(abbreviation: suffix, expansion: text)
            }
            if matched {
                return nil
            }
        }
        return nil
    }

    func trimToPossibleSuffix(_ buffer: String) -> String {
        for i in buffer.indices {
            let suffix = String(buffer[i...])
            if trie.search(suffix).matched {
                return suffix
            }
        }
        return ""
    }
}
