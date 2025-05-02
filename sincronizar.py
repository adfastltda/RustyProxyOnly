#!/usr/bin/python
# -*- coding: utf-8 -*-
# atlasremove.py
import os
import sys
import time
import threading
from concurrent.futures import ThreadPoolExecutor

def fix_lines(lines):
    fixed_lines = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        # Check if line is non-empty and starts with alphanumeric (letter or digit)
        if line and (line[0].isalnum()):
            parts = line.split()
            # If line has less than 4 parts, try to combine with next line
            if len(parts) < 4 and i + 1 < len(lines):
                next_line = lines[i + 1].strip()
                next_parts = next_line.split()
                # Combine current line with next line if it contains continuation data
                if next_parts and (next_parts[0].isalnum() or next_parts[0].startswith('-')):
                    parts.extend(next_parts)
                    i += 2  # Skip next line
                else:
                    i += 1
            else:
                i += 1
            # Ensure the line has at least 4 parts before adding
            if len(parts) >= 4:
                # Format the line to include exactly the first 4 parts
                fixed_lines.append(f"{parts[0]} {parts[1]} {parts[2]} {parts[3]}")
            else:
                # If still not enough parts, skip or handle as needed
                print(f"Skipping malformed line: {line}")
        else:
            i += 1
    return fixed_lines

def process_line(linha):
    colunas = linha.split()
    if len(colunas) >= 4:
        # Check if there's a fifth column for v2rayadd
        if len(colunas) >= 5:
            os.system("./dragonmodule v2rayadd " + colunas[4] + " " + colunas[0] + " " + colunas[1] + " " + colunas[2] + " " + colunas[3])
        else:
            os.system("./dragonmodule createssh " + colunas[0] + " " + colunas[1] + " " + colunas[2] + " " + colunas[3])
    else:
        print(f"Ignoring invalid line: {linha}")

if len(sys.argv) != 2:
    print("Uso: python atlasremove.py <nome_do_arquivo>")
    sys.exit(1)

nome_arquivo = sys.argv[1]

with open(nome_arquivo, 'r') as arquivo:
    linhas = arquivo.readlines()
    linhas = [linha for linha in linhas if linha.strip()]
    
    # Fix the lines before processing
    linhas = fix_lines(linhas)

    # Use ThreadPoolExecutor to process lines with 100 threads
    with ThreadPoolExecutor(max_workers=100) as executor:
        executor.map(process_line, linhas)

    arquivo.close()
    os.system("cp " + nome_arquivo/sincronizar.py /root/)
    os.system("rm " + nome_arquivo)
    os.system("sudo systemctl restart v2ray")
