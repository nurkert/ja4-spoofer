import csv
import collections
import sys

def analyze(filepath):
    print(f"Analyzing {filepath}...")
    interpreter_counts = collections.Counter()
    browser_counts = collections.Counter()
    total_rows = 0

    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            for row in reader:
                total_rows += 1
                interp = row.get('interpreter', '').strip()
                brows = row.get('browser', '').strip()
                
                # Count non-empty values
                if interp and interp.lower() != 'none':
                    interpreter_counts[interp] += 1
                if brows and brows.lower() != 'none':
                    browser_counts[brows] += 1
                
                if total_rows % 500000 == 0:
                    print(f"Processed {total_rows} rows...", file=sys.stderr)

    except Exception as e:
        print(f"Error reading file: {e}")
        return

    print(f"\nTotal Rows: {total_rows}")

    print("\nTop 20 Interpreters (Share in Database):")
    for name, count in interpreter_counts.most_common(20):
        share = (count / total_rows) * 100
        print(f"{name}: {count} ({share:.2f}%)")

    print("\nTop 20 Browsers (Share in Database):")
    for name, count in browser_counts.most_common(20):
        share = (count / total_rows) * 100
        print(f"{name}: {count} ({share:.2f}%)")

if __name__ == "__main__":
    analyze('assets/ja3_database.csv')
