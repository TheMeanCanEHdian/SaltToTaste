import os, re, requests
from collections import defaultdict
from datetime import datetime
from saltToTaste.parser_handler import argparser_results

argument = argparser_results()
DATA_DIR = os.path.abspath(argument['DATA_DIR'])

def recipe_importer(directory):
    list = []
    for file in os.listdir(directory):
        recipe = dict(recipe_parser(file, directory))
        recipe_formatted = recipe_formater(recipe)
        list.append(recipe_formatted)
    return list

def recipe_parser(recipe, directory, encoding='utf-16'):
    recipe_dict = defaultdict(list)
    current_key = None

    regex_string = re.compile(r'(?:(?P<key>.*?):\s*|)(?P<value>.*)') # or r'(?:(.*?):\s*|)(.*)'

    with open(f'{directory}/{recipe}', 'r', encoding=encoding) as recipe:
        for line in recipe:
            line = line.strip('\n').rstrip(' ') #clean up the line
            if line in ('', '---'): # make sure line isn't empty or '---', could remove '---' if just made the files text instead of markdown
                continue

            key, value = regex_string.match(line).groups() # match key and value groups

            # lines with "key:"
            if key and not value:
                recipe_dict[key] = []
                current_key = key  # remember the current key
                continue

            # lines with "key: value"
            elif key and value:
                recipe_dict[key].append(value)

            # lines with just "value"
            elif not key and value:
                recipe_dict[current_key].append(value)
    if recipe_dict['layout']:
        recipe_dict['layout'] = recipe_dict['layout'][0]
    if recipe_dict['title']:
        recipe_dict['title'] = recipe_dict['title'][0]
    if recipe_dict['tags']:
        recipe_dict['tags'] = recipe_dict['tags'][0]
    if recipe_dict['image']:
        recipe_dict['image'] = recipe_dict['image'][0]
    if recipe_dict['imagecredit']:
        recipe_dict['imagecredit'] = recipe_dict['imagecredit'][0]
    if recipe_dict['source']:
        recipe_dict['source'] = recipe_dict['source'][0]
    if recipe_dict['description']:
        recipe_dict['description'] = recipe_dict['description'][0]
    if recipe_dict['prep']:
        recipe_dict['prep'] = recipe_dict['prep'][0]
    if recipe_dict['cook']:
        recipe_dict['cook'] = recipe_dict['cook'][0]
    if recipe_dict['ready']:
        recipe_dict['ready'] = recipe_dict['ready'][0]
    if recipe_dict['servings']:
        recipe_dict['servings'] = recipe_dict['servings'][0]
    if recipe_dict['calories']:
        recipe_dict['calories'] = recipe_dict['calories'][0]
    recipe_dict['last_modified'] = datetime.fromtimestamp(os.stat(recipe.name).st_mtime)
    recipe_dict['filename'] = os.path.basename(recipe.name)
    return recipe_dict

def recipe_formater(recipe):
    recipe['title'] = recipe['title'].strip('"')
    if recipe['tags']:
        recipe['tags'] = recipe['tags'].split(', ')
    recipe['ingredients'] = [x.lstrip('- ') for x in recipe['ingredients']]
    recipe['directions'] = [x.lstrip('- ') for x in recipe['directions']]
    recipe['notes'] = [x.lstrip('- ') for x in recipe['notes']]
    return recipe

def delete_recipe_file(filename):
    file_path = f'./_recipes/{filename}'
    if os.path.exists(file_path):
        os.remove(file_path)
        print (f' - Deleting {filename} from disk')
        return True
    else:
        return False

def delete_recipe_image(image):
    image_path = f'{DATA_DIR}/_images/{image}'
    if os.path.exists(image_path):
        os.remove(image_path)
        print (f' - Deleting {image} from disk')

def download_image(link, title_formatted):
    r = requests.get(link)
    open(f'{DATA_DIR}/_images/{title_formatted}.jpg', 'wb').write(r.content)
    print (f' + Saved {title_formatted}.jpg to disk')

def add_recipe_file(recipe_data):
    formatted_title = recipe_data["title"].replace(" ", "_").lower()
    f = open(f'{DATA_DIR}/_recipes/{formatted_title}.txt', 'w+', encoding='utf-16')
    f.seek(0)
    f.write(f'layout: {recipe_data["layout"]}\n')
    f.write(f'title: "{recipe_data["title"]}"\n')
    f.write(f'image: {recipe_data["image"] or ""}\n')
    f.write(f'imagecredit: {recipe_data["imagecredit"] or ""}\n')
    tags = ""
    if recipe_data['tags']:
        for tag in recipe_data['tags']:
            tags = tags + (f'{tag}, ')
        tags = tags.rstrip(", ")
    f.write(f'tags: {tags}\n')
    f.write(f'source: {recipe_data["source"] or ""}\n')
    f.write(f'\nprep: {recipe_data["prep"] or ""}\n')
    f.write(f'cook: {recipe_data["cook"] or ""}\n')
    f.write(f'ready: {recipe_data["ready"] or ""}\n')
    f.write(f'servings: {recipe_data["servings"] or ""}\n')
    f.write(f'calories: {recipe_data["calories"] or ""}\n\n')
    if recipe_data['description']:
        f.write(f'description:\n{recipe_data["description"].replace(":", ";")}\n')
    else:
        f.write(f'description:\n\n')
    if recipe_data['ingredients']:
        f.write('\ningredients:\n')
        for ingredient in recipe_data['ingredients']:
            f.write(f'- {ingredient}\n')
    else:
        f.write('\ningredients:\n\n')
    if recipe_data['directions']:
        f.write('\ndirections:\n')
        for direction in recipe_data["directions"]:
            f.write(f'- {direction}\n')
    else:
        f.write('\ndirections:\n\n')
    if recipe_data['notes']:
        f.write('\nnotes:\n')
        for note in recipe_data['notes']:
            f.write(f'- {note}\n')
    else:
        f.write('\nnotes:\n')
    f.close()
    print (f' + Saved {formatted_title}.txt to disk')
