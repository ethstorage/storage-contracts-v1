import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

import statistics
import sys

import es_mining

diff_adj = 1/1024
if len(sys.argv) > 1:
    diff_adj = 1 / int(sys.argv[1])

alg = 'grow_to_diff'
# alg = 'iterations'
if len(sys.argv) > 2:
    alg = sys.argv[2]

num_simulations = 100
if len(sys.argv) > 3:
    num_simulations = int(sys.argv[3])

final_times = []
target_block_time = 3 * 3600
one_replica_diff = target_block_time / 12 * 1024 * 1024

if alg == 'grow_to_diff':
    init_diff = one_replica_diff * 10
    target_diff_or_iterations = one_replica_diff * 20
elif alg == 'drop_to_diff':
    init_diff = one_replica_diff * 40
    target_diff_or_iterations = one_replica_diff * 20
else:
    init_diff = one_replica_diff * 20
    target_diff_or_iterations = 1000

all_block_times = []
for i in range(num_simulations):
    total_time, times, _, _, _, block_times = es_mining.mine(
        diff_adj, init_diff, target_diff_or_iterations, target_block_time, alg=alg)

    final_times.append(total_time / 3600)
    all_block_times.extend(block_times)
    print("Finish %d simulation, diff adj times: %d" % (i, len(times)))

if alg == 'grow_to_diff' or alg == 'drop_to_diff':
    print("Grow stats")
    mean_value = statistics.mean(final_times)
    variance_value = statistics.variance(final_times)
    std_dev = statistics.stdev(final_times)

    print("Mean value:", mean_value)
    print("Variance value:", variance_value)
    print("Standard variance value:", std_dev)

    coefficient_of_variation = std_dev / mean_value if mean_value != 0 else None
    print("Coefficient of variation:", coefficient_of_variation)

    plt.figure(figsize=(12.8, 9.6))
    plt.hist(final_times, bins=50)
    plt.xlabel('Final Time (hours)')
    plt.ylabel('Frequency')
    plt.title('Distribution of Final Times in Simulations')
    ax = plt.gca()
    ax.xaxis.set_major_locator(ticker.MaxNLocator(integer=True))

    plt.show()
else:
    print("Print block time stats")
    mean_value = statistics.mean(block_times)
    variance_value = statistics.variance(block_times)
    std_dev = statistics.stdev(block_times)

    print("Mean value:", mean_value)
    print("Variance value:", variance_value)
    print("Standard variance value:", std_dev)

    coefficient_of_variation = std_dev / mean_value if mean_value != 0 else None
    print("Coefficient of variation:", coefficient_of_variation)
