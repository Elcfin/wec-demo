#include <getopt.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>

#include <iostream>
#include <cstdint>
#include <vector>
#include <string>
#include <fstream>
#include <chrono>
#include <mutex>
#include <thread>

#include "isa-l.h"

using namespace std;
using namespace std::chrono;

// Native implementation of Galois Field arithmetic for Reed-Solomon coding
class GaloisField {
private:
    uint8_t log_table[256];
    uint8_t exp_table[256];
    
public:
    GaloisField() {
        // Initialize tables for GF(2^8) arithmetic with primitive polynomial x^8 + x^4 + x^3 + x^2 + 1 (0x11D)
        uint16_t x = 1;
        for (int i = 0; i < 255; i++) {
            exp_table[i] = x & 0xFF;
            
            // Compute log table
            log_table[exp_table[i]] = i;
            
            // Multiply by x (equivalent to left shift and conditional XOR with the primitive polynomial)
            x <<= 1;
            if (x & 0x100)
                x ^= 0x11D; // XOR with the primitive polynomial if overflow
        }
        
        // Handle special cases
        exp_table[255] = exp_table[0]; // For wrap-around in multiplication
        log_table[0] = 0; // Log of 0 is undefined, but we'll use 0 for computation
    }
    
    // Multiply two elements in GF(2^8)
    inline uint8_t multiply(uint8_t a, uint8_t b) const {
        if (a == 0 || b == 0) return 0;
        return exp_table[(log_table[a] + log_table[b]) % 255];
    }
};

// Global instance of GF for efficiency
static GaloisField gf;

// Native implementation of Reed-Solomon erasure coding
void rs_encode_data_native(
    uint64_t len,          // Length of each data/coding block in bytes
    uint64_t k,            // Number of data blocks
    uint64_t m,            // Number of coding blocks to produce
    uint8_t *gftbls,       // Galois Field tables for encoding
    uint8_t **data_ptrs,   // Array of k pointers to data blocks
    uint8_t **coding_ptrs  // Array of m pointers to coding blocks
) {
    // Process each coding block
    for (uint64_t i = 0; i < m; i++) {
        // Process each byte position
        for (uint64_t byte_idx = 0; byte_idx < len; byte_idx++) {
            uint8_t *coding_byte = coding_ptrs[i] + byte_idx;
            uint8_t result = 0;
            
            // For each data block
            for (uint64_t j = 0; j < k; j++) {
                uint8_t data_byte = data_ptrs[j][byte_idx];
                if (data_byte == 0) continue; // Skip multiplication by zero
                
                // Get coefficient from Galois Field table (simplified)
                uint8_t coefficient = gftbls[(i * k + j) * 32]; // Simplified access to coefficient
                
                // Perform Galois Field multiplication and XOR to the result
                result ^= gf.multiply(coefficient, data_byte);
            }
            
            // Store the result
            *coding_byte = result;
        }
    }
}


struct ThreadSafeMetrics
{
    std::mutex mtx;
    double read_time = 0.0;
    double write_time = 0.0; // 写入时间 (模拟网络发送时间)
    double compute_time = 0.0;
    double encoding_time = 0.0;

    // void add_read_time(double t)
    // {
    //     std::lock_guard<std::mutex> lock(mtx);
    //     read_time += t;
    // }
    // void add_write_time(double t)
    // {
    //     std::lock_guard<std::mutex> lock(mtx);
    //     write_time += t;
    // }
    double total_io_time() const { return read_time + write_time; }
    double other_time() const
    {
        return encoding_time - compute_time - total_io_time();
    }
};

struct IOMetrics
{
    double read_time = 0.0;  // 读取时间
    double write_time = 0.0; // 写入时间 (模拟网络发送时间)
    double total_io_time() const { return read_time + write_time; }
};

// 更高性能的文件读取函数，通过内存映射
bool read_block_from_file_mmap(const string &filepath, uint8_t *buffer, uint64_t block_size, double *read_time = nullptr)
{
    auto read_start = high_resolution_clock::now();

    int fd = open(filepath.c_str(), O_RDONLY);
    if (fd == -1)
    {
        cerr << "Error opening file: " << filepath << endl;
        return false;
    }

    void *mapped = mmap(NULL, block_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (mapped == MAP_FAILED)
    {
        cerr << "Error mapping file: " << filepath << endl;
        close(fd);
        return false;
    }

    memcpy(buffer, mapped, block_size);
    munmap(mapped, block_size);
    close(fd);

    auto read_end = high_resolution_clock::now();
    if (read_time)
    {
        *read_time += duration_cast<milliseconds>(read_end - read_start).count() / 1000.0;
    }

    return true;
}

bool write_block_to_file(const string &filepath, const uint8_t *buffer, uint64_t block_size, double *write_time = nullptr)
{
    auto write_start = high_resolution_clock::now();

    ofstream file(filepath, ios::binary | ios::trunc);
    if (!file)
    {
        cerr << "Error: Unable to open file for writing: " << filepath << endl;
        return false;
    }
    file.write(reinterpret_cast<const char *>(buffer), block_size);
    file.close();

    auto write_end = high_resolution_clock::now();
    if (write_time)
    {
        *write_time += duration_cast<milliseconds>(write_end - write_start).count() / 1000.0;
        cout << "Wrote " << block_size << " bytes to " << filepath
             << " in " << duration_cast<milliseconds>(write_end - write_start).count() / 1000.0 << " seconds." << endl;
    }

    return true;
}

void run_stripe(uint64_t x, uint64_t k, uint64_t m, uint64_t block_size, uint64_t stripe_idx, vector<string> &data_block_filepaths, bool verbose, bool chunking, uint64_t chunk_size, uint8_t *gftbl, ThreadSafeMetrics &metrics, bool isal)
{
    // 为当前批次创建复用缓冲区和指针 - 使用aligned_alloc确保16字节对齐
    vector<uint8_t *> data_buffers(x);
    vector<uint8_t *> data_ptrs(x);

    // 分配16字节对齐的内存
    for (uint64_t i = 0; i < x; i++)
    {
        // 使用posix_memalign分配对齐内存
        void *ptr = nullptr;
        if (posix_memalign(&ptr, 16, block_size) != 0)
        {
            cerr << "Error: Failed to allocate aligned memory for data buffer" << endl;
            return;
        }
        data_buffers[i] = static_cast<uint8_t *>(ptr);
        data_ptrs[i] = data_buffers[i];
    }

    // 创建奇偶校验缓冲区 - 同样使用对齐内存
    vector<uint8_t *> parity(m);
    vector<uint8_t *> parity_ptrs(m);

    for (uint64_t i = 0; i < m; i++)
    {
        void *ptr = nullptr;
        if (posix_memalign(&ptr, 16, block_size) != 0)
        {
            cerr << "Error: Failed to allocate aligned memory for parity buffer" << endl;
            return;
        }
        parity[i] = static_cast<uint8_t *>(ptr);
        parity_ptrs[i] = parity[i];
    }

    // 创建临时奇偶校验缓冲区 - 同样使用对齐内存
    vector<uint8_t *> local_parity(m);
    vector<uint8_t *> local_parity_ptrs(m);

    for (uint64_t i = 0; i < m; i++)
    {
        void *ptr = nullptr;
        if (posix_memalign(&ptr, 16, block_size) != 0)
        {
            cerr << "Error: Failed to allocate aligned memory for parity buffer" << endl;
            return;
        }
        local_parity[i] = static_cast<uint8_t *>(ptr);
        local_parity_ptrs[i] = local_parity[i];
    }

    auto start_time = high_resolution_clock::now();
    uint64_t iterations = (k + x - 1) / x;
    for (uint64_t iter = 0; iter < iterations; iter++)
    {
        uint64_t start_idx = iter * x;
        uint64_t end_idx = min(k, (iter + 1) * x);
        uint64_t current_batch_size = end_idx - start_idx;

        if (verbose)
        {
            cout << "  Processing batch " << (iter + 1) << "/" << iterations
                 << " (blocks " << start_idx << " to " << (end_idx - 1) << ")" << endl;
        }

        // 重置临时奇偶校验缓冲区
        for (uint64_t i = 0; i < m; i++)
        {
            memset(local_parity_ptrs[i], 0, block_size);
        }

        for (uint64_t i = 0; i < current_batch_size; i++)
        {
            uint64_t block_idx = start_idx + i;

            // 确保文件存在且可读
            if (access(data_block_filepaths[block_idx].c_str(), F_OK | R_OK) != 0)
            {
                cerr << "Error: File not found or not readable: " << data_block_filepaths[block_idx] << endl;
                throw runtime_error("File access error");
            }

            if (!read_block_from_file_mmap(data_block_filepaths[block_idx], data_ptrs[i], block_size, &metrics.read_time))
            {
                cerr << "Error reading data block " << block_idx << " from file: " << data_block_filepaths[block_idx] << endl;
                throw runtime_error("File read error");
            }
        }

        uint8_t *batch_gftbl = gftbl + start_idx * m * 16;
        if (chunking && chunk_size < block_size)
        {
            uint64_t num_chunks = (block_size + chunk_size - 1) / chunk_size;
            for (uint64_t chunk_idx = 0; chunk_idx < num_chunks; chunk_idx++)
            {
                uint64_t current_chunk_size = min(chunk_size, block_size - chunk_idx * chunk_size);
                uint64_t chunk_offset = chunk_idx * chunk_size;
                vector<uint8_t *> chunk_data_ptrs(current_batch_size);
                vector<uint8_t *> chunk_parity_ptrs(m);

                for (uint64_t i = 0; i < current_batch_size; i++)
                {
                    chunk_data_ptrs[i] = data_ptrs[i] + chunk_offset;
                }

                for (uint64_t i = 0; i < m; i++)
                {
                    chunk_parity_ptrs[i] = local_parity_ptrs[i] + chunk_offset;
                }
                auto compute_start = high_resolution_clock::now();
                rs_encode_data_native(current_chunk_size, current_batch_size, m, batch_gftbl,
                                   chunk_data_ptrs.data(), chunk_parity_ptrs.data());
                // ec_encode_data_sse(current_chunk_size, current_batch_size, m, batch_gftbl,
                //                    chunk_data_ptrs.data(), chunk_parity_ptrs.data());
                auto compute_end = high_resolution_clock::now();
                metrics.compute_time += duration_cast<milliseconds>(compute_end - compute_start).count() / 1000.0;
            }
        }
        else
        {
            auto compute_start = high_resolution_clock::now();
            if(!isal)
            rs_encode_data_native(block_size, current_batch_size, m, batch_gftbl,
                               data_ptrs.data(), local_parity_ptrs.data());
                               else
            ec_encode_data_sse(block_size, current_batch_size, m, batch_gftbl,
                               data_ptrs.data(), local_parity_ptrs.data());
            auto compute_end = high_resolution_clock::now();
            metrics.compute_time += duration_cast<milliseconds>(compute_end - compute_start).count() / 1000.0;
        }

        for (uint64_t i = 0; i < m; i++)
        {
            for (uint64_t j = 0; j < block_size; j++)
            {
                parity_ptrs[i][j] ^= local_parity_ptrs[i][j];
            }
        }
    }

    // 模拟发送奇偶校验数据
    auto send_start = high_resolution_clock::now();
    for (uint64_t i = 0; i < m; i++)
    {
        volatile uint64_t checksum = 0;
        for (uint64_t j = 0; j < block_size; j += 64)
        {
            checksum += parity_ptrs[i][j & (block_size - 1)];
        }
    }
    auto send_end = high_resolution_clock::now();
    metrics.write_time += duration_cast<milliseconds>(send_end - send_start).count() / 1000.0;

    auto end_time = high_resolution_clock::now();
    metrics.encoding_time = duration_cast<milliseconds>(end_time - start_time).count() / 1000.0;
    if (verbose)
    {
        cout << "=== Stripe Encoding Completed ===" << endl;
        cout << "  Compute time: " << metrics.compute_time << " seconds" << endl;
        cout << "  I/O overhead: " << metrics.total_io_time() << " seconds" << endl;
        cout << "    - Read time: " << metrics.read_time << " seconds" << endl;
        cout << "    - Network send time (simulated): " << metrics.write_time << " seconds" << endl;
        cout << "  Total time: " << metrics.encoding_time << " seconds" << endl;
        cout << "  Other overhead: " << metrics.other_time() << " seconds" << endl;
    }

    // 释放对齐分配的内存
    for (uint64_t i = 0; i < x; i++)
    {
        free(data_buffers[i]);
    }

    for (uint64_t i = 0; i < m; i++)
    {
        free(parity[i]);
    }

    for (uint64_t i = 0; i < m; i++)
    {
        free(local_parity[i]);
    }
}

void run_stripe_thread(
    uint64_t x, uint64_t k, uint64_t m, uint64_t block_size,
    uint64_t start_stripe, uint64_t end_stripe,
    vector<vector<string>> data_block_filepaths,
    bool verbose, bool chunking, uint64_t chunk_size, uint8_t *gftbl,
    ThreadSafeMetrics &global_metrics, bool isal)
{
    for (uint64_t stripe = start_stripe; stripe < end_stripe; ++stripe)
    {
        if (verbose)
        {
            cout << "Thread " << std::this_thread::get_id()
                 << " processing stripe " << stripe + 1 << endl;
        }
        ThreadSafeMetrics local_metrics;
        // 调用原 run_stripe（需调整返回值，或直接在这里统计时间）
        run_stripe(x, k, m, block_size, stripe, data_block_filepaths[stripe], verbose, chunking, chunk_size, gftbl, local_metrics, isal);
        global_metrics.mtx.lock();
        global_metrics.read_time += local_metrics.read_time;
        global_metrics.write_time += local_metrics.write_time;
        global_metrics.compute_time += local_metrics.compute_time;
        global_metrics.encoding_time += local_metrics.encoding_time;
        global_metrics.mtx.unlock();
    }
}

void run(uint64_t k, uint64_t m, uint64_t block_size, ofstream &outfile, bool verbose, uint64_t stripes_count, uint64_t x, uint64_t y, string temp_dir, bool chunking, uint64_t chunk_size, bool isal)
{
    const uint64_t encoding_memory_footprint = k * block_size;
    const uint64_t parity_memory_footprint = m * block_size;
    const uint64_t max_op_memory = encoding_memory_footprint + parity_memory_footprint;
    const uint64_t max_system_memory = (uint64_t)16 * 1024 * 1024 * 1024;
    if (max_op_memory > max_system_memory)
    {
        cerr << "Error: The memory footprint for encoding (" << max_op_memory
             << " bytes) exceeds the maximum system memory limit (" << max_system_memory
             << " bytes). Please reduce k, m, or block_size." << endl;
        return;
    }

    const uint64_t n = k + m;
    vector<uint8_t> matrix(k * n, 0);
    vector<uint8_t> gftbl(k * m * 32, 0);
    uint8_t *encode_matrix_ptr = matrix.data() + k * k;

    gf_gen_cauchy1_matrix(matrix.data(), n, k);
    ec_init_tables(k, m, encode_matrix_ptr, gftbl.data());

    vector<vector<string>> data_block_filepaths(stripes_count, vector<string>(k));

    if (verbose)
        cout << "Initializing temporary data files..." << endl;
    // 使用 /dev/shm 作为临时目录
    // string temp_dir = "/dev/shm";
    // string temp_dir = "/home/elcfin/shm";
    // vector<uint8_t> pattern_buffer(block_size);
    for (int stripe = 0; stripe < stripes_count; stripe++)
    {
        for (uint64_t i = 0; i < k; ++i)
        {
            // if (stripe % 2)
            //     data_block_filepaths[stripe][i] = temp_dir + "/large_data_s0_b" + to_string(i) + ".tmp";
            // else
            //     data_block_filepaths[stripe][i] = temp_dir + "/large_data_s1_b" + to_string(i) + ".tmp";
            data_block_filepaths[stripe][i] = temp_dir + "/large_data_s" + to_string(stripe) + "_b" + to_string(i) + ".tmp";

            // 数据已经持久化
            // for (uint64_t j = 0; j < block_size; ++j)
            // {
            //     pattern_buffer[j] = static_cast<uint8_t>((stripe * k * block_size + i * block_size + j) % 256);
            // }
            // if (!write_block_to_file(data_block_filepaths[stripe][i], pattern_buffer.data(), block_size))
            // {
            //     cerr << "Error: Failed to write initial data to temporary file: " << data_block_filepaths[stripe][i] << endl;
            //     return;
            // }
        }
    }

    if (verbose)
        cout << "Temporary data files initialized." << endl;

    // 读取和编码统计
    ThreadSafeMetrics metrics;

    auto encode_start = high_resolution_clock::now();

    vector<ThreadSafeMetrics> thread_metrics(y);
    vector<std::thread> threads;

    uint64_t stripe_per_thread = stripes_count / y;
    uint64_t remainder = stripes_count % y;

    uint64_t start_stripe = 0;
    for (uint64_t i = 0; i < y; ++i)
    {
        uint64_t end_stripe = start_stripe + stripe_per_thread;
        if (i < remainder)
        {
            end_stripe += 1; // 分配剩余的 stripe
        }

        // 启动线程
        threads.emplace_back(
            run_stripe_thread,
            x, k, m, block_size,
            start_stripe, end_stripe,
            data_block_filepaths,
            verbose, chunking, chunk_size, gftbl.data(),
            std::ref(thread_metrics[i]), isal);

        start_stripe = end_stripe;
    }

    // 等待所有线程完成
    for (auto &th : threads)
    {
        th.join();
    }

    double max_encoding_time = 0.0;
    uint64_t max_id = 0;
    for (uint64_t i = 0; i < y; ++i)
    {
        if (thread_metrics[i].encoding_time > max_encoding_time)
        {
            max_encoding_time = thread_metrics[i].encoding_time;
            max_id = i;
        }
    }
    metrics.read_time = thread_metrics[max_id].read_time;
    metrics.write_time = thread_metrics[max_id].write_time;
    metrics.compute_time = thread_metrics[max_id].compute_time;
    metrics.encoding_time = thread_metrics[max_id].encoding_time;

    auto encode_end = high_resolution_clock::now();
    metrics.encoding_time = duration_cast<milliseconds>(encode_end - encode_start).count() / 1000.0;

    const uint64_t total_data_size = k * block_size * stripes_count;
    double encode_throughput = 0.0;
    if (metrics.encoding_time > 0)
    {
        encode_throughput = total_data_size / (1024.0 * 1024.0) / metrics.encoding_time; // MB/s
    }
    else
    {
        encode_throughput = 0.0;
    }

    if (verbose)
    {
        cout << "\n=== In-Memory EC Encoding Completed ===" << endl;
        cout << "Total encoding time: " << metrics.encoding_time << " seconds" << endl;
        cout << "  Computation time: " << metrics.compute_time << " seconds";
        if (metrics.encoding_time > 0)
            cout << " (" << (metrics.compute_time / metrics.encoding_time * 100.0) << "% of total)";
        cout << endl;
        cout << "  Computation throughput: " << (total_data_size / (1024.0 * 1024.0) / metrics.compute_time) << " MB/s" << endl;
        cout << "  I/O overhead: " << metrics.total_io_time() << " seconds";
        if (metrics.encoding_time > 0)
            cout << " (" << (metrics.total_io_time() / metrics.encoding_time * 100.0) << "% of total)";
        cout << endl;
        cout << "    - Read time: " << metrics.read_time << " seconds" << endl;
        cout << "    - Network send time (simulated): " << metrics.write_time << " seconds" << endl;
        cout << "  Other overhead: " << metrics.other_time() << " seconds";
        if (metrics.encoding_time > 0)
            cout << " (" << (metrics.other_time() / metrics.encoding_time * 100.0) << "% of total)";
        cout << endl;
        cout << "Encoding throughput: " << encode_throughput << " MB/s" << endl;
    }

    if (outfile.is_open())
    {
        outfile << "RS," << k << "," << m << "," << x << "," << y << "," << (block_size / (1024.0 * 1024.0)) << "," << (chunk_size / (1024.0))  <<","<< (total_data_size / (1024.0 * 1024.0)) << ","
                << metrics.encoding_time << "," << encode_throughput << ","
                << metrics.compute_time << "," << metrics.total_io_time() << ","
                << metrics.read_time << "," << metrics.write_time << ","
                << metrics.other_time() << "," << isal << "\n";
    }

    // 清理临时文件
    // if (verbose)
    //     cout << "Cleaning up temporary files..." << endl;

    // for (uint64_t stripe = 0; stripe < stripes_count; ++stripe)
    // {
    //     for (uint64_t i = 0; i < k; ++i)
    //     {
    //         if (remove(data_block_filepaths[stripe][i].c_str()) != 0)
    //         {
    //             cerr << "Warning: Failed to remove temporary file: " << data_block_filepaths[stripe][i] << endl;
    //         }
    //     }
    // }
}

// main函数保持不变
int main(int argc, char *argv[])
{
    uint64_t k = 64;
    uint64_t m = 4;
    uint64_t block_size = 32 * 1024 * 1024;
    string output_file = "";
    bool verbose = false;
    uint64_t stripes_count = 16;
    uint64_t part_per_stripe = 32; // x
    uint64_t xy = 64;
    // uint64_t parallel_count = 2;   // y
    string temp_dir = "/dev/shm"; // /home/elcfin/shm
    bool chunking = false;
    uint64_t chunk_size = 64 * 1024; // 64KB
    bool isal = false;

    static struct option long_options[] = {
        {"help", no_argument, 0, 'h'},
        {"k", required_argument, 0, 'k'},
        {"block_size", required_argument, 0, 'b'},
        {"batch", no_argument, 0, 't'},
        {"output", required_argument, 0, 'o'},
        {"verbose", no_argument, 0, 'v'},
        {"temp_dir", required_argument, 0, 'f'},
        {"stripes", required_argument, 0, 's'},
        {"part_per_stripe", required_argument, 0, 'x'},
        // {"parallel_count", required_argument, 0, 'y'},
        {"xy", required_argument, 0, 'a'},
        {"chunking", no_argument, 0, 'c'},
        {"chunk_size", required_argument, 0, 'z'},
        {"isal", no_argument, 0, 'i'},
        {0, 0, 0, 0}};

    int opt;
    while ((opt = getopt_long(argc, argv, "hk:b:o:vf:s:x:a:cz:i", long_options, nullptr)) != -1)
    {
        switch (opt)
        {
        case 'h':
            cout << "Usage: memory_demo [options]\n"
                 << "Options:\n"
                 << "  -h, --help            Display this help message\n"
                 << "  -k, --k N             Set number of data blocks (default: 64)\n"
                 << "  -b, --block_size N    Set block size in kb (default: 32MB)\n"
                 << "  -o, --output          Output results to a file\n"
                 << "  -v, --verbose         Enable verbose output\n"
                 << "  -f, --temp_dir <dir> Temporary directory for data files (default: /dev/shm)\n"
                 << "  -s, --stripes N       Set number of stripes (default: 10)\n"
                 << "  -x, --part_per_stripe N Set number of parts per stripe (default: 32)\n"
                 << "  -a, --xy N            Set x and y (default: 64)\n"
                 //  << "  -y, --parallel_count N Set parallel count (default: 2)\n";
                 << "  -c, --chunking        Enable chunking mode\n"
                 << "  -z, --chunk_size N    Set chunk size in bytes (default: 64KB)\n"
                 << "  -i, --isal            Use Intel ISA-L for encoding (default: false)\n";
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
            output_file = optarg;
            break;
        case 'v':
            verbose = true;
            break;
        case 'f':
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
        case 'x':
            part_per_stripe = atoi(optarg);
            if (part_per_stripe < 1)
            {
                cerr << "Error: Number of parts per stripe must be at least 1" << endl;
                return 1;
            }
            break;
        // case 'y':
        //     parallel_count = atoi(optarg);
        //     if (parallel_count < 1)
        //     {
        //         cerr << "Error: Parallel count must be at least 1" << endl;
        //         return 1;
        //     }
        //     break;
        case 'a':
            xy = atoi(optarg);
            break;
        case 'c':
            chunking = true;
            if (verbose)
            {
                cout << "Chunking mode enabled." << endl;
            }
            break;
        case 'z':
            chunk_size = atoi(optarg) * 1024 * 1024; // 转换为字节
            break;
        case 'i':
            isal = true;
            if (verbose)
            {
                cout << "Intel ISA-L mode enabled." << endl;
            }
            break;
        default:
            cerr << "Unknown option: " << char(opt) << endl;
            return 1;
        }
    }
    if (verbose)
    {
        cout << "Verbose mode enabled." << endl;
    }
    else
    {
        cout << "Chunking mode disabled." << endl;
    }
    if (!output_file.empty())
    {
        cout << "Output will be saved to: " << output_file << endl;
    }
    else
    {
        cout << "No output file specified." << endl;
    }

    ofstream outfile;
    if (!output_file.empty())
    {
        // output_file = "./res/P_C_" + output_file + ".csv";
        outfile.open(output_file);
        if (outfile.is_open())
        {
            outfile << "code_type,k,m,x,y,block_size,chunk_size(KB),total_data_size,encode_time,encode_throughput,"
                    << "compute_time,io_time,read_time,simulated_send_time,other_time,isa-l\n";
            cout << "Output file opened successfully." << endl;
        }
        else
        {
            cerr << "Unable to open output file: " << output_file << endl;
            return 1;
        }
    }

    cout << "=== Starting single test ===" << endl;
    uint64_t test_x = part_per_stripe;
    uint64_t test_y = xy / test_x;
    run(k, m, block_size, outfile, verbose, stripes_count, test_x, test_y, temp_dir, chunking, chunk_size, isal);

    if (outfile.is_open())
    {
        outfile.close();
    }

    return 0;
}