import matplotlib.pyplot as plt
import numpy as np
import os
from collections import defaultdict


def visualize_point_cloud(file_path):
    """
    Loads and displays a categorized 3D point cloud as a scatter plot,
    visualizing the sensor's range with a dome and floor.

    Args:
        file_path (str): The path to the categorized point cloud file.
    """
    if not os.path.exists(file_path):
        print(f"Error: File not found at '{file_path}'")
        return

    objects = defaultdict(list)

    try:
        with open(file_path, "r") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) == 4:
                    x, y, z = float(parts[0]), float(parts[1]), float(parts[2])
                    name = parts[3]
                    objects[name].append([x, y, z])

        if not objects:
            print("Error: No valid data found in the file.")
            return

        for name in objects:
            objects[name] = np.array(objects[name])

        fig = plt.figure(figsize=(14, 10))
        ax = fig.add_subplot(111, projection="3d")
        colors = plt.cm.get_cmap("gist_rainbow", len(objects))

        # --- Plot each object's points ---
        for i, (name, points) in enumerate(objects.items()):
            godot_x, godot_y_up, godot_z = points[:, 0], points[:, 1], points[:, 2]
            # Plot the points as a simple scatter plot
            ax.scatter(godot_x, godot_z, godot_y_up, s=10, label=name, color=colors(i))

        # --- Calculate max range and draw dome/floor ---
        all_points = np.vstack(list(objects.values()))
        distances = np.linalg.norm(all_points, axis=1)
        max_dist = np.max(distances)
        dome_radius = max_dist * 1.05  # Add a small buffer

        # Create the floor circle
        theta = np.linspace(0, 2 * np.pi, 100)
        floor_x = dome_radius * np.cos(theta)
        floor_z = dome_radius * np.sin(theta)
        ax.plot(
            floor_x,
            floor_z,
            0,
            color="gray",
            linestyle="--",
            label="Sensor Floor Range",
        )

        # Create the hemisphere (dome)
        u = np.linspace(0, 2 * np.pi, 50)
        v = np.linspace(0, np.pi / 2, 50)
        dome_x = dome_radius * np.outer(np.cos(u), np.sin(v))
        dome_z = dome_radius * np.outer(np.sin(u), np.sin(v))
        dome_y_up = dome_radius * np.outer(np.ones(np.size(u)), np.cos(v))
        ax.plot_wireframe(
            dome_x, dome_z, dome_y_up, color="gray", alpha=0.3, rstride=5, cstride=5
        )

        ax.scatter(
            0,
            0,
            0,
            s=150,
            color="black",
            marker="x",
            label="Sensor Origin",
            depthshade=False,
        )

        # --- Customize the Plot ---
        ax.set_title("LiDAR Point Cloud and Sensor Range")
        ax.set_xlabel("X-axis"), ax.set_ylabel("Z-axis (Depth)"), ax.set_zlabel(
            "Y-axis (Up)"
        )
        ax.legend(loc="upper left", bbox_to_anchor=(1.05, 1))
        fig.tight_layout()
        ax.view_init(elev=25, azim=45)

        # --- Set equal aspect ratio ---
        x_coords, y_coords, z_coords = (
            all_points[:, 0],
            all_points[:, 2],
            all_points[:, 1],
        )
        mid_x, mid_y, mid_z = np.mean(x_coords), np.mean(y_coords), np.mean(z_coords)
        max_range_plot = max(
            x_coords.max() - x_coords.min(),
            y_coords.max() - y_coords.min(),
            z_coords.max() - z_coords.min(),
            dome_radius * 2,
        )
        half_range = max_range_plot / 2.0

        ax.set_xlim(mid_x - half_range, mid_x + half_range)
        ax.set_ylim(mid_y - half_range, mid_y + half_range)
        ax.set_zlim(0, max_range_plot)  # Start floor at 0

        print("Displaying plot. Close the plot window to exit the script.")
        plt.show()

    except Exception as e:
        print(f"An error occurred: {e}")


if __name__ == "__main__":
    filename = "point_cloud_categorized.txt"
    visualize_point_cloud(filename)
