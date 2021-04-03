import numpy as np
import matplotlib.pyplot as plt
import sys

if len(sys.argv) != 3:
    sys.exit('Wrong number of arguments: ' + str(len(sys.argv) - 1))

file_path = sys.argv[1]
plot_path = sys.argv[2]

# print("Path to source file = " + file_path)
# print("Path to image file = " + plot_path)

data = np.genfromtxt(file_path, delimiter=',', skip_header=1)
params = np.unique(data[:,0])

for param in params:
    sub_data = data[data[:,0] == param]
    plt.plot(sub_data[:,1], sub_data[:,2], label=str(int(param)) + " %")

plt.xlabel('Operations planned')
plt.ylabel('Operations executed')
plt.legend()

plt.savefig(plot_path)
