import cv2
import numpy as np

import matplotlib.pyplot as plt

import os
import sys

from pathlib import Path

DETAIL = 1024
O = 1
Q = 1
R = 1
S = 1
T = 1

'''
PARAMS:
64 50 500 
64 -1 1 
64 0.05 1 
64 -1 1 
'''

# theta = 0
# phi = 0

# rho = 

# def X(mu, v):

# def A(mu, v):


# for i in range(DETAIL):
#     for j in range(DETAIL):
#         # calculate initial values
#         # get generalized 


def load_txt_to_numpy(filename):
    try:
        # Load the data
        data = np.genfromtxt(filename, delimiter=' ', dtype=float, invalid_raise=False)

        # Validate that we have the expected structure
        if data.size == 0:
            raise ValueError("File is empty")

        # If we have a 1D array (single line), reshape it
        if data.ndim == 1:
            data = data.reshape(1, -1)

        # Check that each row has exactly 64 elements
        if data.shape[1] != 64:
            raise ValueError(f"Expected 64 numbers per line, got{data.shape[1]}")

        return data

    except FileNotFoundError:
        raise FileNotFoundError(f"File '{filename}' not found")
    except Exception as e:
        raise ValueError(f"Error loading file: {str(e)}")


def process_all_txt_files(folder_path, output_folder):

    # Convert to Path object for easier handling
    folder = Path(folder_path)

    # Check if folder exists
    if not folder.exists():
        raise FileNotFoundError(f"Folder '{folder_path}' not found")

    # Find all txt files in the folder
    txt_files = list(folder.glob("*.txt"))

    if not txt_files:
        print(f"No .txt files found in '{folder_path}'")
        return {}

    print(f"Found {len(txt_files)} txt files in '{folder_path}'")

    with open("PATH\\final_proj_python\\output_images\\array_outputs.txt", "w") as file:
        
        # Process each txt file
        for txt_file in txt_files:
            try:
                img = load_txt_to_numpy(txt_file)

                # Optionally save processed results
                if output_folder:
                    output_path = Path(output_folder)
                    output_path.mkdir(exist_ok=True)

                    # max = 65535/np.max(img)
                    # img_high_depth_monochrome = (img*max).astype('uint16')
                    
                    # cv2.imwrite("final_proj_python\\output_images\\" + txt_file.name + "_" + str(max) +".png", img_high_depth_monochrome)
                    # print(txt_file.name)

                    file.write(f"float {txt_file.name.split('.',1)[0].replace('-','_')}[64][64] = ")
                    file.write("{\n")
                    for i, row in enumerate(img):
                        row_list_formatted = [f"{str(v)}f" for v in row]
                        # print(", ".join(row_list_formatted))
                        file.write("{")
                        file.write(", ".join(row_list_formatted))
                        # # for j, val in enumerate(row):
                        # #     file.write(f"{val}f, ")
                        file.write("},\n")
                    
                    # print((img).shape)
                    file.write("};\n\n")

            except Exception as e:
                print(f"  Error processing {txt_file.name}: {str(e)}")
    
# name = "LogGaussAniso_A_15p"
    

# img = load_txt_to_numpy("final_proj_python\\txtfiles\\" + name + ".txt")
# print(img)

# cv2.imwrite("final_proj_python\\Log_Gauss_Aniso_A.png", img)

# max = 65535/np.max(img)

# print(img*max)

# print((img*max).astype('uint16'))

# img_high_depth_monochrome = (img*max).astype('uint16')

# cv2.imwrite("final_proj_python\\output_images\\" + name +".png", img_high_depth_monochrome)

process_all_txt_files("PATH\\final_proj_python\\tables","PATH\\final_proj_python\\output_images")

# all_files = ["LogGaussAniso_P_1.txt",
# "LogGaussAniso_P_15p.txt",
# "LogGaussAniso_P_2.txt",
# "LogGaussAniso_P_3.txt",
# "LogGaussAniso_P_4-5.txt",
# "LogGaussAniso_P_6-8.txt",
# "LogGaussAniso_P_9-14.txt",
# "LogGaussAniso_X_1.txt",
# "LogGaussAniso_X_15p.txt",
# "LogGaussAniso_X_2.txt",
# "LogGaussAniso_X_3.txt",
# "LogGaussAniso_X_4-5.txt",
# "LogGaussAniso_X_6-8.txt",
# "LogGaussAniso_X_9-14.txt",
# "LogGaussAniso_A_1.txt",
# "LogGaussAniso_A_15p.txt",
# "LogGaussAniso_A_2.txt",
# "LogGaussAniso_A_3.txt",
# "LogGaussAniso_A_4-5.txt",
# "LogGaussAniso_A_6-8.txt",
# "LogGaussAniso_A_9-14.txt",
# "LogGaussAniso_B1_1.txt",
# "LogGaussAniso_B1_15p.txt",
# "LogGaussAniso_B1_2.txt",
# "LogGaussAniso_B1_3.txt",
# "LogGaussAniso_B1_4-5.txt",
# "LogGaussAniso_B1_6-8.txt",
# "LogGaussAniso_B1_9-14.txt",
# "LogGaussAniso_B2_1.txt",
# "LogGaussAniso_B2_15p.txt",
# "LogGaussAniso_B2_2.txt",
# "LogGaussAniso_B2_3.txt",
# "LogGaussAniso_B2_4-5.txt",
# "LogGaussAniso_B2_6-8.txt",
# "LogGaussAniso_B2_9-14.txt",
# "LogGaussAniso_C_1.txt",
# "LogGaussAniso_C_15p.txt",
# "LogGaussAniso_C_2.txt",
# "LogGaussAniso_C_3.txt",
# "LogGaussAniso_C_4-5.txt",
# "LogGaussAniso_C_6-8.txt",
# "LogGaussAniso_C_9-14.txt",
# "LogGaussAniso_D_1.txt",
# "LogGaussAniso_D_15p.txt",
# "LogGaussAniso_D_2.txt",
# "LogGaussAniso_D_3.txt",
# "LogGaussAniso_D_4-5.txt",
# "LogGaussAniso_D_6-8.txt",
# "LogGaussAniso_D_9-14.txt"]

# fig, axes = plt.subplots(7,7)
# for i, ax in enumerate(axes.flat):
#     ax.imshow(load_txt_to_numpy("final_proj_python\\tables\\" + all_files[i]))

# plt.show()