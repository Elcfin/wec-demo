import pandas as pd
import sys

def sort_csv_by_k(input_file, output_file):
    """使用 pandas 按 'k' 列排序 CSV 文件"""
    try:
        # 读取 CSV 文件
        df = pd.read_csv(input_file)
        
        # 检查是否存在 'k' 列
        if 'k' not in df.columns:
            raise ValueError("CSV 文件中未找到 'k' 列，请检查文件格式")
        
        # 按 'k' 列数值排序（转为整数确保正确排序）
        df['k'] = df['k'].astype(int)  # 强制转为整数，避免字符串排序问题
        df_sorted = df.sort_values(by='k')
        
        # 保存排序后的文件（不保留 pandas 索引）
        df_sorted.to_csv(output_file, index=False)
        
        print(f"✅ 排序完成！已保存到 {output_file}")
        print(f"📊 排序前行数：{len(df)}，排序后行数：{len(df_sorted)}")
        
    except FileNotFoundError:
        print(f"❌ 错误：输入文件 '{input_file}' 不存在")
        sys.exit(1)
    except ValueError as e:
        print(f"❌ 错误：{e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ 发生未知错误：{str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    # 检查命令行参数
    if len(sys.argv) != 3:
        print("⚠️ 用法：python csv_sort.py <输入CSV路径> <输出CSV路径>")
        print("示例：python csv_sort.py data.csv sorted_data.csv")
        sys.exit(1)
    
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    
    sort_csv_by_k(input_path, output_path)