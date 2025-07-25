#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>
#include <algorithm>
#include <numeric>
#include <random>
#include <chrono>
#include <thread>
#include <immintrin.h>

// Use CPUID to serialize instructions before RDTSC
inline uint64_t rdtsc()
{
  uint32_t low, high;
  asm volatile(
      "cpuid\n\t" // Serialize instructions
      "rdtsc\n\t"
      : "=a"(low), "=d"(high)::"%rbx", "%rcx");
  return ((uint64_t)high << 32) | low;
}

// Measure TSC frequency
double measure_tsc_freq()
{
  auto start = std::chrono::steady_clock::now();
  uint64_t tsc_start = rdtsc();
  std::this_thread::sleep_for(std::chrono::milliseconds(100));
  uint64_t tsc_end = rdtsc();
  auto end = std::chrono::steady_clock::now();

  auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
  return (tsc_end - tsc_start) * 1e9 / ns; // cycles/second
}

// Pointer chasing latency measurement
double measure_pointer_chase_latency(uint64_t buffer_size, int iterations, bool warm_cache)
{
  const uint64_t cache_line = 64;
  uint64_t num_nodes = buffer_size / cache_line;
  if (num_nodes < 2)
  {
    std::cerr << "Buffer too small for pointer chasing!" << std::endl;
    return -1;
  }

  // Allocate aligned memory
  uint8_t *buffer;
  if (posix_memalign((void **)&buffer, cache_line, buffer_size) != 0)
  {
    std::cerr << "Memory allocation failed!" << std::endl;
    return -1;
  }

  // Cast to Node structure
  struct Node
  {
    Node *next;
    uint8_t padding[cache_line - sizeof(Node *)];
  };
  static_assert(sizeof(Node) == cache_line, "Node size mismatch");

  Node *nodes = reinterpret_cast<Node *>(buffer);

  // Create random permutation
  std::vector<uint64_t> indices(num_nodes);
  std::iota(indices.begin(), indices.end(), 0);
  std::shuffle(indices.begin(), indices.end(), std::mt19937{std::random_device{}()});

  // Build circular linked list
  for (uint64_t i = 0; i < num_nodes; ++i)
  {
    nodes[i].next = &nodes[indices[(i + 1) % num_nodes]];
  }

  // Warm cache if requested
  if (warm_cache)
  {
    for (uint64_t i = 0; i < num_nodes; ++i)
    {
      _mm_clflush(&nodes[i]); // Ensure cache is cold first
    }
    Node *current = nodes;
    for (uint64_t i = 0; i < num_nodes; ++i)
    {
      current = current->next;
    }
  }

  // Measure TSC overhead
  uint64_t tsc_overhead = 0;
  for (int i = 0; i < 100; ++i)
  {
    uint64_t start = rdtsc();
    uint64_t end = rdtsc();
    tsc_overhead += end - start;
  }
  tsc_overhead /= 100;

  // Pointer chasing
  volatile const Node *current = nodes;
  std::vector<uint64_t> cycles(iterations);

  for (int i = 0; i < iterations; ++i)
  {
    uint64_t start = rdtsc();
    asm volatile("" : : : "memory"); // Prevent compiler reordering
    current = current->next;
    asm volatile("" : : : "memory"); // Prevent compiler reordering
    uint64_t end = rdtsc();

    cycles[i] = (end - start - tsc_overhead);
  }

  // Compute median to avoid outliers
  std::sort(cycles.begin(), cycles.end());
  double avg_cycles = cycles[iterations / 2];

  free(buffer);
  return avg_cycles;
}

int main()
{
  // Measure actual TSC frequency
  double tsc_freq = measure_tsc_freq();
  double ns_per_cycle = 1e9 / tsc_freq;
  std::cout << "TSC Frequency: " << tsc_freq / 1e9 << " GHz" << std::endl;

  // Measure L1 cache latency (32KB)
  double l1_cycles = measure_pointer_chase_latency(
      32 * 1024, // 32KB buffer
      100000,    // Iterations
      true       // Warm cache
  );
  double l1_latency = l1_cycles * ns_per_cycle;

  // Measure RAM latency (20MB)
  double ram_cycles = measure_pointer_chase_latency(
      20 * 1024 * 1024, // 20MB buffer
      10000,            // Fewer iterations for RAM
      false             // No cache warming
  );
  double ram_latency = ram_cycles * ns_per_cycle;

  std::cout << "L1 Cache Latency (32KB): " << l1_cycles << " cycles" << std::endl;
  std::cout << "RAM Latency (20MB): " << ram_cycles << " cycles" << std::endl;
  std::cout << "L1 Cache Latency: " << l1_latency << " ns" << std::endl;
  std::cout << "RAM Latency: " << ram_latency << " ns" << std::endl;

  return 0;
}