import Darwin
import Foundation

print("\(CommandLine.arguments)")

let map = try MemoryMap(url: URL(string: "file:///Users/jabwd/Desktop/memorymap.txt")!)

for n in 0..<10_000 {
    let str = "Line #\(n)\n"
    var buff = Array(str.utf8)
    try map.write(bytes: &buff)
}
