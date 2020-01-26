import os
import argparse
import configparser

def create_argparser():
    parser = argparse.ArgumentParser(description='A Flask based recipe platform')
    parser.add_argument('--datadir', help='Specify a directory to store your data files')
    return parser

def argparser_results():
    parser = create_argparser()
    args = parser.parse_args()
    results = {
        'DATA_DIR' : None
    }

    if args.datadir:
        results['DATA_DIR'] = args.datadir.rstrip('/')
    else:
        results['DATA_DIR'] = "config"

    return results

def configparser_results(file):
    config = configparser.ConfigParser()

    config.read(file)

    if not config.has_section('flask'):
        return False

    return config
