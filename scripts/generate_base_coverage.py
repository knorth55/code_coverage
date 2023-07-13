#!/usr/bin/env python

import argparse
import glob
import json
import magic
import os


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('base_dir', type=str)
    parser.add_argument('--output', '-o', type=str, default='.')
    args = parser.parse_args()

    python_filepaths = list_python_filepaths(os.path.abspath(args.base_dir))
    coverage_lines = {}
    for python_filepath in python_filepaths:
        coverage_lines[python_filepath] = []
    coverage_dict = {"lines": coverage_lines}
    coverage_txt = '!coverage.py: This is a private format, don\'t read it directly!\n'
    coverage_txt += json.dumps(coverage_dict)
    os.makedirs(args.output, exist_ok=True)
    with open(os.path.join(args.output, '.coverage'), 'w') as coverage_f:
        coverage_f.write(coverage_txt)


def list_python_filepaths(base_dir):
    python_directories = [
        'bin',
        'node_scripts',
        'src',
        'scripts',
    ]
    python_filepaths = []
    for python_dir in python_directories:
        for filepath in glob.glob(os.path.join(base_dir, python_dir, '**'), recursive=True):
            if os.path.isfile(filepath):
                fileext = os.path.splitext(filepath)[1]
                if (fileext == '.py' or
                        (fileext == '' and 'Python' in magic.from_file(filepath))):
                    python_filepaths.append(filepath)
    return sorted(set(python_filepaths))


if __name__ == '__main__':
    main()
