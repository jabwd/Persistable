import Darwin

print("\(CommandLine.arguments)")

print("PageSize: \(getpagesize())")

let fd = open(
    "persistable.txt",
    O_RDWR | O_CREAT,
    S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
)

guard fd > 0 else {
    fatalError("Unable to open file")
}

var st: stat = stat()
guard fstat(fd, &st) == 0 else {
    fatalError("Unable to read file statistics")
}

var fileSize: off_t = st.st_size

print("FileSize: \(fileSize)")

var address = mmap(nil, Int(fileSize), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
guard address != MAP_FAILED else {
    fatalError("Unable to map file \(errno) \(address) \(MAP_FAILED)")
}

var rc: Int32 = 0
for n in 0..<100 {
    let line = "This is line #\(n)\n"
    var buff: [UInt8] = Array(line.utf8)
    let oldSize = fileSize
    fileSize += Int64(buff.count)
    if ftruncate(fd, fileSize) != 0 {
        fatalError("Unable to increase filesize")
    }

    rc = munmap(address, Int(oldSize))
    if rc == -1 {
        fatalError("Unable to unmap memory")
    }
    address = mmap(nil, Int(fileSize), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
    if address == MAP_FAILED {
        fatalError("Unable to increase mmap filesize")
    }

    memcpy(address! + UnsafeMutableRawPointer.Stride(oldSize), &buff, buff.count)
}

guard msync(address, Int(fileSize), MS_SYNC) >= 0 else {
    fatalError("Unable to sync file")
}

guard munmap(address, Int(fileSize)) != -1 else {
    fatalError("Unable to free memory mapped file")
}

if close(fd) == 1 {
    fatalError("Unable to close file descriptor")
}

/*

 int main(int argc,char *argv[])
 {
 int fd, ret;
 size_t len_file, len;
 struct stat st;
 char *addr;
 char buf[MAX];

 while ((fgets(buf,MAX,stdin)) != NULL)
 {
 len = len_file;
 len_file += strlen(buf);
 if (ftruncate(fd, len_file) != 0)
 {
 perror("Error extending file");
 return EXIT_FAILURE;
 }
 if ((addr = mremap(addr, len, len_file, MREMAP_MAYMOVE)) == MAP_FAILED)
 {
 perror("Error extending mapping");
 return EXIT_FAILURE;
 }
 memcpy(addr+len, buf, len_file - len);
 printf( "Val:%s\n",addr ) ; //Checking purpose
 }
 if((msync(addr,len,MS_SYNC)) < 0)
 perror("Error in msync");

 if (munmap(addr,len) == -1)
 perror("Error in munmap");

 if (close(fd))
 perror("Error in close");

 return 0;
 }
 */
