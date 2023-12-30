import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

import statistics
import sys

import es_mining

diff_adj = 1/1024
if len(sys.argv) > 1:
    diff_adj = 1 / int(sys.argv[1])

final_times = []
num_simulations = 1000

for i in range(num_simulations):
    total_time, _, _, _, _ = es_mining.mine(diff_adj)

    final_times.append(total_time / 3600)
    print("Finish %d simulation" % i)

mean_value = statistics.mean(final_times)
variance_value = statistics.variance(final_times)
std_dev = statistics.stdev(final_times)

print("Mean value:", mean_value)
print("Variance value:", variance_value)
print("Standard variance value:", std_dev)

coefficient_of_variation = std_dev / mean_value if mean_value != 0 else None
print("Coefficient of Variation:", coefficient_of_variation)


plt.figure(figsize=(12.8, 9.6))
plt.hist(final_times, bins=50)
plt.xlabel('Final Time (hours)')
plt.ylabel('Frequency')
plt.title('Distribution of Final Times in Simulations')
ax = plt.gca()
ax.xaxis.set_major_locator(ticker.MaxNLocator(integer=True))

plt.show()
