#include <cstdint>
#include <iostream>
#include <vector>
#include <algorithm>
#include <random>
#include <immintrin.h>
#include <chrono>
#include <thread>

// 改进的RDTSC：添加内存屏障
inline uint64_t rdtsc()
{
  uint32_t low, high;
  asm volatile(
      "mfence\n\t" // 内存屏障
      "lfence\n\t" // 加载屏障
      "rdtsc\n\t"
      : "=a"(low), "=d"(high)::"memory");
  return ((uint64_t)high << 32) | low;
}

// 伽罗瓦域乘法表
class GF256
{
private:
  static const uint8_t modulus = 0x1B; // x^8 + x^4 + x^3 + x + 1
  static constexpr size_t TABLE_SIZE = 256;
  uint8_t mul_table[TABLE_SIZE][TABLE_SIZE];

  uint8_t multiply_no_table(uint8_t a, uint8_t b) const
  {
    uint8_t p = 0;
    for (int i = 0; i < 8; i++)
    {
      if (b & 1)
        p ^= a;
      bool carry = a & 0x80;
      a <<= 1;
      if (carry)
        a ^= modulus;
      b >>= 1;
    }
    return p;
  }

public:
  GF256()
  {
    for (int a = 0; a < TABLE_SIZE; a++)
    {
      for (int b = 0; b < TABLE_SIZE; b++)
      {
        mul_table[a][b] = multiply_no_table(a, b);
      }
    }
  }

  uint8_t multiply(uint8_t a, uint8_t b) const
  {
    return mul_table[a][b];
  }
};

// 精确测量GF乘法延迟
void measure_gf_mult_latency(const GF256 &gf)
{
  const int warmup_iterations = 10000;
  const int measure_iterations = 1000000;
  const uint64_t MAX_ALLOWED_CYCLES = 1000; // 合理上限

  // 准备随机输入
  std::mt19937 rng(std::random_device{}());
  std::uniform_int_distribution<uint8_t> dist(0, 255);
  std::vector<uint8_t> coefficients(measure_iterations);
  std::vector<uint8_t> data_bytes(measure_iterations);
  for (int i = 0; i < measure_iterations; ++i)
  {
    coefficients[i] = dist(rng);
    data_bytes[i] = dist(rng);
  }

  // 预热：填充缓存
  volatile uint8_t sink = 0;
  for (int i = 0; i < warmup_iterations; ++i)
  {
    sink = gf.multiply(coefficients[i], data_bytes[i]);
  }
  (void)sink; // 避免未使用警告

  // 测量RDTSC开销（使用中位数）
  std::vector<uint64_t> overhead_samples(100);
  for (int i = 0; i < 100; ++i)
  {
    uint64_t start = rdtsc();
    uint64_t end = rdtsc();
    overhead_samples[i] = end - start;
  }
  std::sort(overhead_samples.begin(), overhead_samples.end());
  const uint64_t tsc_overhead = overhead_samples[50]; // 中位数

  // 实际测量
  std::vector<uint64_t> cycles;
  cycles.reserve(measure_iterations);

  for (int i = 0; i < measure_iterations; ++i)
  {
    uint8_t a = coefficients[i];
    uint8_t b = data_bytes[i];

    uint64_t start = rdtsc();
    asm volatile("" : : : "memory");
    uint8_t result = gf.multiply(a, b);
    asm volatile("" : : : "memory");
    uint64_t end = rdtsc();

    // 防止优化
    asm volatile("" : "+r"(result) : : "memory");

    uint64_t delta = end - start;

    // 过滤异常值
    if (delta >= tsc_overhead && delta < MAX_ALLOWED_CYCLES)
    {
      cycles.push_back(delta - tsc_overhead);
    }
  }

  // 确保有足够有效样本
  if (cycles.size() < measure_iterations / 2)
  {
    std::cerr << "警告：超过50%的样本被丢弃！" << std::endl;
  }

  // 计算统计信息
  std::sort(cycles.begin(), cycles.end());
  const size_t count = cycles.size();

  double min = count > 0 ? cycles[0] : 0;
  double median = count > 0 ? cycles[count / 2] : 0;
  double avg = 0;
  for (auto c : cycles)
    avg += c;
  avg = count > 0 ? avg / count : 0;
  double p90 = count > 0 ? cycles[static_cast<size_t>(count * 0.90)] : 0;
  double p99 = count > 0 ? cycles[static_cast<size_t>(count * 0.99)] : 0;
  double max = count > 0 ? cycles.back() : 0;

  // 输出结果
  std::cout << "GF(256) Multiply Latency Statistics:\n";
  std::cout << "  Valid samples: " << count << "/" << measure_iterations << "\n";
  std::cout << "  RDTSC overhead: " << tsc_overhead << " cycles\n";
  std::cout << "  Minimum:    " << min << " cycles\n";
  std::cout << "  Median:     " << median << " cycles\n";
  std::cout << "  Average:    " << avg << " cycles\n";
  std::cout << "  90th %ile:  " << p90 << " cycles\n";
  std::cout << "  99th %ile:  " << p99 << " cycles\n";
  std::cout << "  Maximum:    " << max << " cycles\n";
}

int main()
{
  // 提高进程优先级（需要sudo）
  // const int prio = nice(-20);

  // 锁定CPU频率（需要root）
  // system("cpupower frequency-set --governor performance");

  // 初始化伽罗瓦域
  GF256 gf;

  // 测量延迟
  measure_gf_mult_latency(gf);

  // 恢复设置
  // system("cpupower frequency-set --governor powersave");
  return 0;
}