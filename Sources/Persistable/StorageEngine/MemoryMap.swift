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

let PAGE_SIZE: Int = Int(getpagesize())

struct MapHeader {
    let writePointer: Int
    let deletedBlocks: [Range<Int>]
}

enum MemoryMapError: Error {
    case accessDenied
    case unableToOpenFile(Int32)
    case metadataError(Int32)
    case errorMappingMemory(Int32)
    case unableToAllocateMemory(Int32)
    case diskSyncFailed(Int32)
}

internal final class MemoryMap {
    private let fd: Int32
    private var size: Int
    private var writePointer: Int
    private var address: UnsafeMutableRawPointer

    init(url: URL) throws {
        let rc = open(
            url.relativePath,
            O_RDWR | O_CREAT,
            S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
        )
        guard rc > 0 else {
            if errno == EACCES {
                throw MemoryMapError.accessDenied
            }
            throw MemoryMapError.unableToOpenFile(errno)
        }
        self.fd = rc

        // We need to determine the initial file size
        var fileStats: stat = stat()
        guard fstat(rc, &fileStats) == 0 else {
            if errno == EACCES {
                throw MemoryMapError.accessDenied
            }
            throw MemoryMapError.metadataError(errno)
        }
        var mapSize = Int(fileStats.st_size)
        let readWritePtr = mapSize != 0
        self.writePointer = mapSize

        // If our file got created by ourselves, there is 0 size available and we should
        // consider allocating the first block in the file, but keep the writepointer at 0
        // so we can use the new available size if needed.
        // We allocate in pagesizes everytime we want more memory
        if !readWritePtr {
            mapSize = PAGE_SIZE
            self.writePointer = 0
        }

        let mapAddress = mmap(
            nil,
            mapSize,
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

        // If the file is newly created we need to ensure we have a block
        // available for writing
        if !readWritePtr {
            guard ftruncate(fd, Int64(mapSize)) == 0 else {
                throw MemoryMapError.unableToAllocateMemory(errno)
            }

            // Write an empty writeptr header to the file
            var empty: Int = 0
            memcpy(address, &empty, MemoryLayout<Int>.size)
            self.writePointer += MemoryLayout<Int>.size
        } else {
            // Attempt to read the writePtr from storage, so we know where we left off!
            var ptr: Int = 0
            memcpy(&ptr, address, MemoryLayout<Int>.size)
            self.writePointer = ptr
        }
    }

    deinit {
        try? commit()
        munmap(address, size)
        shutdown(fd, O_RDWR)
        close(fd)
    }

    // MARK: -

    func write(data: Data) throws {
        var buff = Array(data)
        try write(bytes: &buff)
    }


    /// Writes the given data buffer to the memory mapped file
    /// - Parameter bytes: Any buffer
    /// - Throws: Throws an error if not enough space is available and no more memory can be allocated
    ///           on iOS this can occur when nearing 1GiB of buffer data
    func write(bytes: inout [UInt8]) throws {
        try increaseSizeIfNeeded(bytes.count)
        memcpy(address + UnsafeMutableRawPointer.Stride(writePointer), &bytes, bytes.count)
        writePointer += bytes.count
        try commit()
    }

    func read(_ range: Range<Int>) -> [UInt8]? {
        nil
    }

    // MARK: -


    /// Reads the amount of bytes needed and the amount of space available in the current
    ///  writing block of the memory map. Allocates more blocks as needed or does nothing
    ///  when enough space is already available
    /// - Parameter requestedBytes: Minimum amount of bytes that should be avalaible for writing
    /// - Throws: In case no more memory can be allocated
    private func increaseSizeIfNeeded(_ requestedBytes: Int) throws {
        // In case we need more bytes, lets allocate some extra pages
        // We allocate in chunks of PAGE_SIZE to hopefully be more efficient
        let neededBytes = (requestedBytes + writePointer) - size
        guard neededBytes > 0 else {
            return
        }
        let pagesNeeded = (neededBytes / PAGE_SIZE) + (neededBytes % PAGE_SIZE > 0 ? 1 : 0)
        let newSize = size + pagesNeeded * PAGE_SIZE
        guard ftruncate(fd, Int64(newSize)) == 0 else {
            throw MemoryMapError.unableToAllocateMemory(errno)
        }

        #if os(Linux)
        guard let newAddr = mremap(address, size, newSize, MREMAP_MAYMOVE) else {
            throw MemoryMapError.unableToAllocateMemory(errno)
        }
        guard newAddr != MAP_FAILED else {
            throw MemoryMapError.errorMappingMemory(errno)
        }
        address = newAddr
        size = newSize
        #else
        guard munmap(address, size) != -1 else {
            throw MemoryMapError.unableToAllocateMemory(errno)
        }
        guard let newAddr = mmap(nil, newSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0) else {
            throw MemoryMapError.unableToOpenFile(errno)
        }
        guard newAddr != MAP_FAILED else {
            throw MemoryMapError.errorMappingMemory(errno)
        }
        address = newAddr
        size = newSize
        #endif
    }


    /// Requests the kernel to write all unsynchronized data to disk
    /// - Throws: throws an error if synchronization fails with a given `ERRNO` error code
    private func commit() throws {
        var ptr = self.writePointer
        memcpy(address, &ptr, MemoryLayout<Int>.size)
        guard msync(address, size, MS_SYNC) == 0 else {
            throw MemoryMapError.diskSyncFailed(errno)
        }
    }
}
