import random
import matplotlib.pyplot as plt

interval = 12
one_replica_mining_power = 1024 * 1024
total_mining_power = one_replica_mining_power * 20


def mine(diff_adj, init_diff, target_diff_or_iterations, target_block_time, alg='grow_to_diff'):
    times = [0]
    difficulties = [init_diff]
    difficulty = init_diff
    time_elapsed = 0
    total_time = 0
    increase_times = 0
    decrease_times = 0
    target_diff = None
    iterations = None
    block_times = []
    if alg == 'grow_to_diff' or alg == 'drop_to_diff':
        target_diff = target_diff_or_iterations
    elif alg == 'iterations':
        iterations = target_diff_or_iterations
    else:
        raise RuntimeError("unsupported alg")
    
    target_block_time_cutoff = target_block_time * 2 // 3

    while True:
        if target_diff is not None:
            if alg == 'grow_to_diff' and difficulty >= target_diff:
                break
            elif alg == 'drop_to_diff' and difficulty <= target_diff:
                break
        if iterations is not None and len(difficulties) > iterations:
            break

        # mining_probability = total_mining_power / difficulty
        # mining_success = random.random() < mining_probability

        time_elapsed = int(random.expovariate(total_mining_power / difficulty)) * 12

        # if mining_success:
        block_time = time_elapsed
        block_times.append(time_elapsed)

        # if block_time < target_block_time:
        #     difficulty += diff_adj * difficulty
        #     increase_times += 1
        # else:
        #     multiple = ((block_time // target_block_time) - 1)
        #     difficulty -= multiple * diff_adj * difficulty
        #     if multiple > 0:
        #         decrease_times += 1
        adjfac = max(1 - block_time // target_block_time_cutoff, -99) * diff_adj
        difficulty = difficulty * (1 + adjfac)
        if difficulty > difficulties[-1]:
            increase_times += 1
        elif difficulty < difficulties[-1]:
            decrease_times += 1

        new_time = times[-1] + block_time / 3600
        times.append(new_time)
        difficulties.append(difficulty)

        total_time += block_time
        time_elapsed = 0
        # else:
        #     time_elapsed += interval
    return total_time, times, difficulties, increase_times, decrease_times, block_times


def main():
    target_block_time = 3 * 3600
    one_replica_diff = target_block_time / 12 * 1024 * 1024
    init_diff = one_replica_diff * 10
    target_diff = one_replica_diff * 20
    _, times, difficulties, itimes, dtimes, _ = mine(1/1024, init_diff, target_diff, target_block_time)
    print("adjustment times is %d, increase times is %d, decrease times is %d" % (
        len(times), itimes, dtimes))
    plt.plot(times, difficulties, marker='o')
    plt.xlabel('Time (hours)')
    plt.ylabel('Difficulty')
    plt.title('Mining Difficulty Over Time')
    plt.grid(True)
    plt.show()


if __name__ == "__main__":
    main()
