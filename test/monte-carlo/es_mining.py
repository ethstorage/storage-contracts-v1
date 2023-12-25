import random
import matplotlib.pyplot as plt

target_block_time = 3 * 3600
one_replica_diff = target_block_time / 12 * 1024 * 1024
init_diff = one_replica_diff * 10
target_diff = one_replica_diff * 20

interval = 12
one_replica_mining_power = 1024 * 1024
total_mining_power = one_replica_mining_power * 20


def mine(diff_adj):
    times = [0]
    difficulties = [init_diff]
    difficulty = init_diff
    time_elapsed = 0
    total_time = 0

    while difficulty < target_diff:
        mining_probability = total_mining_power / difficulty
        mining_success = random.random() < mining_probability

        if mining_success:
            block_time = time_elapsed

            if block_time < target_block_time:
                difficulty += (1 - (block_time / target_block_time)
                               ) * diff_adj * difficulty
            else:
                difficulty -= ((block_time / target_block_time) -
                               1) * diff_adj * difficulty

            new_time = times[-1] + block_time / 3600
            times.append(new_time)
            difficulties.append(difficulty)

            total_time += block_time
            time_elapsed = 0
        else:
            time_elapsed += interval
    return total_time, times, difficulties


def main():
    _, times, difficulties = mine(1/1024)
    plt.plot(times, difficulties, marker='o')
    plt.xlabel('Time (hours)')
    plt.ylabel('Difficulty')
    plt.title('Mining Difficulty Over Time')
    plt.grid(True)
    plt.show()


if __name__ == "__main__":
    main()
