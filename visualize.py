import matplotlib.pyplot as plt
import numpy as np
import os
import sys
import glob
from collections import defaultdict

# ---------------------------------------------------------------------------
# Coordinate System Notes
# ---------------------------------------------------------------------------
# Matplotlib's mplot3d assumes Z is "up" (vertical on screen) in its default
# rendering. Godot (and many 3D engines) use a right‑handed system with Y up.
# To display data in a right‑handed Y‑up frame inside Matplotlib we:
#   1. Keep data in native (X, Y, Z) with Y as up.
#   2. When plotting, swap axes so that (X, Z, Y) is passed to Matplotlib,
#      because Matplotlib's Z axis is the vertical one we want to represent Y.
#   3. Relabel the axes so users see X (right), Z (forward/depth), Y (up).
#   4. (Optional) Invert the depth axis if you prefer -Z forward conventions.
# This preserves a right‑handed orientation: X × Y = Z.

Y_UP_DISPLAY = True  # Toggle if you want raw Matplotlib (Z up) instead.


def visualize_point_cloud(file_path):
    """
    Loads and displays a categorized 3D point cloud as a scatter plot,
    visualizing the sensor's range with a dome and floor.
    """
    if not os.path.exists(file_path):
        print(f"Error: File not found at '{file_path}'")
        return

    objects = defaultdict(list)
    scanner_pos = np.array([0.0, 0.0, 0.0])  # Default to origin
    scanner_rot_deg = (0.0, 0.0)  # Default yaw, pitch in degrees for display
    yaw_rad = 0.0  # Default yaw in radians for calculation

    try:
        with open(file_path, "r") as f:
            for line in f:
                line = line.strip()
                # Parse header for scanner position and rotation
                if line.startswith("# SCANNER_POS:"):
                    scanner_pos = np.array([float(x) for x in line.split()[2:]])
                elif line.startswith("# SCANNER_ROT:"):
                    # Read yaw and pitch in radians
                    yaw_rad, pitch_rad = [float(x) for x in line.split()[2:]]
                    # Store degrees for display title
                    # yaw_rad = (yaw_rad - np.pi / 2) % (2 * np.pi)
                    scanner_rot_deg = (np.rad2deg(yaw_rad), np.rad2deg(pitch_rad))
                elif line and not line.startswith("#"):
                    parts = line.split()
                    if len(parts) == 4:
                        x, y, z = float(parts[0]), float(parts[1]), float(parts[2])
                        name = parts[3]
                        objects[name].append([x, y, z])

        if not objects:
            print(f"Error: No valid point data found in '{file_path}'.")
            return

        # Convert to numpy arrays and make points relative to the scanner's position
        for name in objects:
            objects[name] = np.array(objects[name]) - scanner_pos

        fig = plt.figure(figsize=(14, 10))
        ax = fig.add_subplot(111, projection="3d")
        colors = plt.cm.get_cmap("gist_rainbow", len(objects))

        # --- Plot each object's points ---
        for i, (name, points) in enumerate(objects.items()):
            if Y_UP_DISPLAY:
                # points: (X, Y, Z) with Y up. Map to (X, Z, Y) so Matplotlib's Z shows Y.
                x_vals, y_up, z_vals = points[:, 0], points[:, 1], points[:, 2]
                ax.scatter(-x_vals, z_vals, y_up, s=10, label=name, color=colors(i))
            else:
                # Standard Matplotlib Z‑up (no remap)
                ax.scatter(
                    points[:, 0],
                    points[:, 1],
                    points[:, 2],
                    s=10,
                    label=name,
                    color=colors(i),
                )

        # --- Calculate max range and draw dome/floor ---
        all_points = np.vstack(list(objects.values()))
        distances = np.linalg.norm(all_points, axis=1)
        max_dist = np.max(distances)
        dome_radius = max_dist * 1.05  # Add a small buffer

        # --- Draw Front Indicator Line (Rotated by Yaw) ---
        # Godot's +Z is the initial front, which maps to Matplotlib's +Y axis.
        # We rotate this vector around the Y-up axis (Matplotlib's Z-up) by the yaw.
        # But since the line is on the floor (Z=0), it's a simple 2D rotation.
        # Godot X maps to plot X, Godot Z maps to plot Y.
        # Rotation of (0,1) by yaw: x' = sin(yaw), y' = cos(yaw)
        front_x = -dome_radius * np.sin(yaw_rad)
        front_z_depth = dome_radius * np.cos(yaw_rad)
        if Y_UP_DISPLAY:
            ax.plot(
                [0, front_x],  # X
                [0, front_z_depth],  # Y axis in plot = world Z (depth)
                [0, 0],  # Z axis in plot = world Y (up)
                color="red",
                linewidth=2.5,
                label="Front Direction",
            )
        else:
            ax.plot(
                [0, front_x],
                [0, 0],
                [0, front_z_depth],
                color="red",
                linewidth=2.5,
                label="Front Direction",
            )

        # Create the floor circle
        theta = np.linspace(0, 2 * np.pi, 100)
        floor_x = dome_radius * np.cos(theta)
        floor_z_depth = dome_radius * np.sin(theta)
        if Y_UP_DISPLAY:
            ax.plot(
                floor_x,
                floor_z_depth,  # depth on Matplotlib Y
                0,  # up (Y) on Matplotlib Z
                color="gray",
                linestyle="--",
                label="Sensor Floor Range",
            )
        else:
            ax.plot(
                floor_x,
                0,
                floor_z_depth,
                color="gray",
                linestyle="--",
                label="Sensor Floor Range",
            )

        # Create the hemisphere (dome)
        u = np.linspace(0, 2 * np.pi, 50)
        v = np.linspace(0, np.pi / 2, 50)
        dome_x = dome_radius * np.outer(np.cos(u), np.sin(v))
        dome_z_depth = dome_radius * np.outer(np.sin(u), np.sin(v))
        dome_y_up = dome_radius * np.outer(np.ones(np.size(u)), np.cos(v))
        if Y_UP_DISPLAY:
            ax.plot_wireframe(
                dome_x,
                dome_z_depth,
                dome_y_up,
                color="gray",
                alpha=0.3,
                rstride=5,
                cstride=5,
            )
        else:
            ax.plot_wireframe(
                dome_x,
                dome_y_up,
                dome_z_depth,
                color="gray",
                alpha=0.3,
                rstride=5,
                cstride=5,
            )

        # Plot the sensor origin
        if Y_UP_DISPLAY:
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
        else:
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
        title = "LiDAR Point Cloud and Sensor Range"
        pos_str = (
            f"Pos: ({scanner_pos[0]:.2f}, {scanner_pos[1]:.2f}, {scanner_pos[2]:.2f})"
        )
        rot_str = (
            f"Rot (Yaw/Pitch): ({scanner_rot_deg[0]:.1f}°, {scanner_rot_deg[1]:.1f}°)"
        )
        title += f"\nScan from {pos_str} | {rot_str}"
        ax.set_title(title)

        if Y_UP_DISPLAY:
            ax.set_xlabel("X (Right)")
            ax.set_ylabel("Z (Forward/Depth)")
            ax.set_zlabel("Y (Up)")
        else:
            ax.set_xlabel("X")
            ax.set_ylabel("Y")
            ax.set_zlabel("Z")
        # ax.legend(loc="upper left", bbox_to_anchor=(1.05, 1))
        fig.tight_layout()
        ax.view_init(elev=25, azim=45)

        # --- Set equal aspect ratio ---
        if Y_UP_DISPLAY:
            # x -> x, depth -> z, up -> y
            x_coords = all_points[:, 0]
            y_coords = all_points[:, 2]  # depth
            z_coords = all_points[:, 1]  # up
        else:
            x_coords = all_points[:, 0]
            y_coords = all_points[:, 1]
            z_coords = all_points[:, 2]
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
        if Y_UP_DISPLAY:
            ax.set_zlim(0, max_range_plot)  # Y up from 0
        else:
            ax.set_zlim(mid_z - half_range, mid_z + half_range)

        if Y_UP_DISPLAY:
            # Slight tweak of viewing angle so Y (up) reads naturally
            ax.view_init(elev=20, azim=45)

        print("Displaying plot. Close the plot window to exit.")
        plt.show()

    except Exception as e:
        print(f"An error occurred: {e}")


def main():
    """Main function to find the file and start visualization."""
    scan_dir = "scans"
    file_to_visualize = ""

    # Check for a command-line argument first.
    if len(sys.argv) > 1:
        file_to_visualize = sys.argv[1]
        print(f"Visualizing specified file: '{file_to_visualize}'")
    else:
        # If no argument, find the latest file in the scans directory.
        print("No file specified. Searching for the latest scan...")
        if not os.path.isdir(scan_dir):
            print(
                f"Error: Scan directory '{scan_dir}' not found. Run the Godot project first to generate scans."
            )
            return

        search_pattern = os.path.join(scan_dir, "point_cloud_categorized_*.txt")
        scan_files = glob.glob(search_pattern)

        if not scan_files:
            print(
                f"Error: No scan files found in '{scan_dir}'. Press Space/Enter in Godot to save a scan."
            )
            return

        # Find the most recently modified file.
        latest_file = max(scan_files, key=os.path.getmtime)
        file_to_visualize = latest_file
        print(f"Found latest file: '{file_to_visualize}'")

    visualize_point_cloud(file_to_visualize)


if __name__ == "__main__":
    main()
