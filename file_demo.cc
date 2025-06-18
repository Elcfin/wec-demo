
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <getopt.h>

#include <cstdint>
#include <string>
#include <vector>
#include <iostream>
#include <fstream>
#include <filesystem>
#include <cstring>

using namespace std;
namespace fs = std::filesystem;

// 使用直接I/O提高性能
bool write_block_to_file(const string &filepath, const uint8_t *buffer, uint64_t block_size)
{
    int fd = open(filepath.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_DIRECT, 0644);
    if (fd == -1)
    {
        cerr << "Error: Unable to open file for writing: " << filepath << " (" << errno << ")" << endl;
        return false;
    }

    // 确保缓冲区对齐
    uint64_t aligned_size = ((block_size + 4095) / 4096) * 4096;
    uint8_t *aligned_buffer = nullptr;
    if (posix_memalign((void **)&aligned_buffer, 4096, aligned_size) != 0)
    {
        cerr << "Error: Failed to allocate aligned memory" << endl;
        close(fd);
        return false;
    }

    memcpy(aligned_buffer, buffer, block_size);

    ssize_t written = pwrite(fd, aligned_buffer, block_size, 0);
    if (written != static_cast<ssize_t>(block_size))
    {
        cerr << "Error: Failed to write entire block to file: " << filepath << endl;
        free(aligned_buffer);
        close(fd);
        return false;
    }

    // 确保数据写入磁盘
    fsync(fd);

    free(aligned_buffer);
    close(fd);
    return true;
}

// 生成pattern并直接写入文件，减少内存使用
bool generate_and_write_pattern(const string &filepath, uint64_t block_size, uint64_t seed)
{
    int fd = open(filepath.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_DIRECT, 0644);
    if (fd == -1)
    {
        cerr << "Error: Unable to open file for writing: " << filepath << " (" << errno << ")" << endl;
        return false;
    }

    // 分配对齐的缓冲区
    uint8_t *buffer = nullptr;
    if (posix_memalign((void **)&buffer, 4096, block_size) != 0)
    {
        cerr << "Error: Failed to allocate aligned memory" << endl;
        close(fd);
        return false;
    }

    // 分块生成并写入，减少内存压力
    const uint64_t chunk_size = 1024 * 1024; // 1MB块
    uint64_t remaining = block_size;
    uint64_t offset = 0;

    while (remaining > 0)
    {
        uint64_t current_chunk = min(chunk_size, remaining);

        // 生成pattern
        for (uint64_t j = 0; j < current_chunk; ++j)
        {
            buffer[j] = static_cast<uint8_t>((seed + j) % 256);
        }

        // 写入文件
        ssize_t written = pwrite(fd, buffer, current_chunk, offset);
        if (written != static_cast<ssize_t>(current_chunk))
        {
            cerr << "Error: Failed to write chunk to file: " << filepath << endl;
            free(buffer);
            close(fd);
            return false;
        }

        remaining -= current_chunk;
        offset += current_chunk;
        seed += current_chunk;
    }

    // 确保数据写入磁盘
    fsync(fd);

    free(buffer);
    close(fd);
    return true;
}

// 清理临时文件
void cleanup_temp_files(const vector<vector<string>> &filepaths)
{
    for (const auto &stripe : filepaths)
    {
        for (const auto &filepath : stripe)
        {
            if (fs::exists(filepath))
            {
                fs::remove(filepath);
            }
        }
    }
}

int main(int argc, char *argv[])
{
    uint64_t k = 128;
    uint64_t m = 4;
    uint64_t block_size = 64 * 1024 * 1024; // 64MB
    uint64_t stripes_count = 2;
    string temp_dir = "/dev/shm"; // "/home/elcfin/shm"

    static struct option long_options[] = {
        {"help", no_argument, 0, 'h'},
        {"k", required_argument, 0, 'k'},
        {"block_size", required_argument, 0, 'b'},
        {"temp_dir", required_argument, 0, 'o'},
        {"stripes", required_argument, 0, 's'},
        {0, 0, 0, 0}};

    int opt;
    while ((opt = getopt_long(argc, argv, "hk:b:o:s:", long_options, nullptr)) != -1)
    {
        switch (opt)
        {
        case 'h':
            cout << "Usage: " << argv[0] << " [options]\n"
                 << "Options:\n"
                 << "  -h, --help          Show this help message\n"
                 << "  -k, --k <num>       Number of data blocks (default: 128)\n"
                 << "  -b, --block_size <size>  Block size in MB (default: 64)\n"
                 << "  -o, --temp_dir <dir> Temporary directory for data files (default: /dev/shm)\n"
                 << "  -s, --stripes <num> Number of stripes (default: 2)\n";
            return 0;
        case 'k':
            k = atoi(optarg);
            if (k < 1)
            {
                cerr << "Error: Number of data blocks must be at least 1" << endl;
                return 1;
            }
            break;
        case 'b':
            block_size = atoi(optarg) * 1024 * 1024; // 转换为字节
            break;
        case 'o':
            temp_dir = optarg;
            break;
        case 's':
            stripes_count = atoi(optarg);
            if (stripes_count < 1)
            {
                cerr << "Error: Number of stripes must be at least 1" << endl;
                return 1;
            }
            break;
        default:
            cerr << "Unknown option: " << char(opt) << endl;
            return 1;
        }
    }

    cout << "Initializing temporary data files..." << endl;
    vector<vector<string>> data_block_filepaths(stripes_count, vector<string>(k));

    // 检查临时目录是否存在
    if (!fs::exists(temp_dir) || !fs::is_directory(temp_dir))
    {
        cerr << "Error: Temporary directory does not exist: " << temp_dir << endl;
        return 1;
    }

    bool success = true;

    try
    {
        for (int stripe = 0; stripe < stripes_count; stripe++)
        {
            for (uint64_t i = 0; i < k; ++i)
            {
                data_block_filepaths[stripe][i] = temp_dir + "/large_data_s" + to_string(stripe) + "_b" + to_string(i) + ".tmp";

                // 计算种子值，保持与原代码相同的pattern生成逻辑
                uint64_t seed = stripe * k * block_size + i * block_size;

                if (!generate_and_write_pattern(data_block_filepaths[stripe][i], block_size, seed))
                {
                    cerr << "Error: Failed to write initial data to temporary file: "
                         << data_block_filepaths[stripe][i] << endl;
                    success = false;
                    throw runtime_error("File write error");
                }

                // 输出进度信息
                if ((stripe * k + i) % 10 == 0)
                {
                    cout << "Progress: " << (stripe * k + i) << "/" << (stripes_count * k) << " files created\r" << flush;
                }
            }
        }
    }
    catch (const exception &e)
    {
        cout << endl
             << "Caught exception: " << e.what() << endl;
        cout << "Cleaning up created files..." << endl;
        cleanup_temp_files(data_block_filepaths);
        return 1;
    }

    cout << endl
         << "Temporary data files initialized." << endl;
    return success ? 0 : 1;
}