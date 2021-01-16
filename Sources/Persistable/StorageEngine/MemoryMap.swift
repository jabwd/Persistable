//
//  MemoryMap.swift
//  
//
//  Created by Antwan van Houdt on 16/01/2021.
//

#if os(Linux)
import GLibc
#else
import Darwin
#endif
import Foundation

enum MemoryMapError: Error {
    case unableToOpenFile(Int32)
    case metadataError(Int32)
    case errorMappingMemory(Int32)
}

internal final class MemoryMap {
    private let fd: Int32
    private var size: Int64
    private var writePointer: Int64
    private var address: UnsafeMutableRawPointer

    init(url: URL) throws {
        var rc = open(
            url.relativePath,
            O_RDWR | O_CREAT,
            S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
        )
        guard rc > 0 else {
            throw MemoryMapError.unableToOpenFile(errno)
        }
        self.fd = rc

        // We need to determine the initial file size
        var fileStats: stat = stat()
        guard fstat(rc, &fileStats) == 0 else {
            throw MemoryMapError.metadataError(errno)
        }
        var mapSize = fileStats.st_size
        self.writePointer = mapSize

        // If our file got created by ourselves, there is 0 size available and we should
        // consider allocating the first block in the file, but keep the writepointer at 0
        // so we can use the new available size if needed.
        // We allocate in pagesizes everytime we want more memory
        if mapSize == 0 {
            mapSize = Int64(getpagesize())
            self.writePointer = 0
        }

        let mapAddress = mmap(
            nil,
            Int(mapSize),
            PROT_READ | PROT_WRITE,
            MAP_SHARED,
            rc,
            0
        )
        guard let finalAddr = mapAddress, mapAddress != MAP_FAILED  else {
            throw MemoryMapError.errorMappingMemory(errno)
        }
        self.size = mapSize
        self.address = finalAddr
    }

    deinit {
        munmap(address, Int(size))
    }

    // MARK: -

    private func increaseSize(_ requestedBytes: Int) {

    }
}
