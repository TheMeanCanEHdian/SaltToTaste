import requests
import os
from saltToTaste.argparser_handler import argparser_results
from saltToTaste.configparser_handler import configparser_results

def fetch_recipe_nutrition(title, servings, ingredient_list):
    argument = argparser_results()
    DATA_DIR = os.path.abspath(argument['DATA_DIR'])
    config = configparser_results(f'{DATA_DIR}/config.ini')

    app_id = config.get('third_party', 'edamam_id')
    app_key = config.get('third_party', 'edamam_key')

    if not app_id or not app_key:
        return False

    print(f' * Searching for nutrition information on {title}')

    params = {'app_id': app_id, 'app_key': app_key}
    headers = {'Content-Type': 'application/json'}
    ingredient_dict = {
        'title': title,
        'yield': servings,
        'ingr': ingredient_list
    }

    r = requests.post('https://api.edamam.com/api/nutrition-details', params=params, headers=headers, json=ingredient_dict)

    if r.status_code != 200:
        print(f" * ERROR: Could not fetch nutrition data. | Code:({r.status_code} Message:{r.json()['error']})")
        return False

    r_json = r.json()

    nutrition_dict = {
        'weight' : r_json.get('totalWeight'),
        'nutrients' : {
            'calcium': r_json['totalNutrients'].get('CA'),
            'carbs':r_json['totalNutrients'].get('CHOCDF'),
            'cholesterol':r_json['totalNutrients'].get('CHOLE'),
            'energy':r_json['totalNutrients'].get('ENERC_KCAL'),
            'fat':r_json['totalNutrients'].get('FAT'),
            'fiber':r_json['totalNutrients'].get('FIBTG'),
            'folate_equivalent':r_json['totalNutrients'].get('FOLDFE'),
            'folate_food':r_json['totalNutrients'].get('FOLFD'),
            'iron':r_json['totalNutrients'].get('FE'),
            'magnesium':r_json['totalNutrients'].get('MG'),
            'monounsaturated':r_json['totalNutrients'].get('FAMS'),
            'niacin_b3':r_json['totalNutrients'].get('NIA'),
            'phosphorus':r_json['totalNutrients'].get('P'),
            'polyunsaturated':r_json['totalNutrients'].get('FAPU'),
            'potassium':r_json['totalNutrients'].get('K'),
            'protein':r_json['totalNutrients'].get('PROCNT'),
            'riboflavin_b2':r_json['totalNutrients'].get('RIBF'),
            'saturated':r_json['totalNutrients'].get('FASAT'),
            'sodium':r_json['totalNutrients'].get('NA'),
            'sugars':r_json['totalNutrients'].get('SUGAR'),
            'sugars_added':r_json['totalNutrients'].get('SUGAR.added'),
            'thiamin_b1':r_json['totalNutrients'].get('THIA'),
            'trans':r_json['totalNutrients'].get('FATRN'),
            'vitamin_a':r_json['totalNutrients'].get('VITA_RAE'),
            'vitamin_b12':r_json['totalNutrients'].get('VITB12'),
            'vitamin_b6':r_json['totalNutrients'].get('VITB6A'),
            'vitamin_c':r_json['totalNutrients'].get('VITC'),
            'vitamin_d':r_json['totalNutrients'].get('VITD'),
            'vitamin_e':r_json['totalNutrients'].get('TOCPHA'),
            'vitamin_k':r_json['totalNutrients'].get('VITK1')
        },
        'daily' : {
            'calcium': r_json['totalDaily'].get('CA'),
            'carbs':r_json['totalDaily'].get('CHOCDF'),
            'cholesterol':r_json['totalDaily'].get('CHOLE'),
            'energy':r_json['totalDaily'].get('ENERC_KCAL'),
            'fat':r_json['totalDaily'].get('FAT'),
            'fiber':r_json['totalDaily'].get('FIBTG'),
            'folate_equivalent':r_json['totalDaily'].get('FOLDFE'),
            'folate_food':r_json['totalDaily'].get('FOLFD'),
            'iron':r_json['totalDaily'].get('FE'),
            'magnesium':r_json['totalDaily'].get('MG'),
            'monounsaturated':r_json['totalDaily'].get('FAMS'),
            'niacin_b3':r_json['totalDaily'].get('NIA'),
            'phosphorus':r_json['totalDaily'].get('P'),
            'polyunsaturated':r_json['totalDaily'].get('FAPU'),
            'potassium':r_json['totalDaily'].get('K'),
            'protein':r_json['totalDaily'].get('PROCNT'),
            'riboflavin_b2':r_json['totalDaily'].get('RIBF'),
            'saturated':r_json['totalDaily'].get('FASAT'),
            'sodium':r_json['totalDaily'].get('NA'),
            'sugars':r_json['totalDaily'].get('SUGAR'),
            'sugars_added':r_json['totalDaily'].get('SUGAR.added'),
            'thiamin_b1':r_json['totalDaily'].get('THIA'),
            'trans':r_json['totalDaily'].get('FATRN'),
            'vitamin_a':r_json['totalDaily'].get('VITA_RAE'),
            'vitamin_b12':r_json['totalDaily'].get('VITB12'),
            'vitamin_b6':r_json['totalDaily'].get('VITB6A'),
            'vitamin_c':r_json['totalDaily'].get('VITC'),
            'vitamin_d':r_json['totalDaily'].get('VITD'),
            'vitamin_e':r_json['totalDaily'].get('TOCPHA'),
            'vitamin_k':r_json['totalDaily'].get('VITK1')
        }
    }

    # Only keep the quantity value for each item
    keys = nutrition_dict['nutrients'].keys()
    for section in ['nutrients', 'daily']:
        for key in keys:
            if nutrition_dict[section][key]:
                nutrition_dict[section][key] = nutrition_dict[section][key]['quantity']

    return nutrition_dict

def fetch_ingredient_nutrition(ingredient):
    argument = argparser_results()
    DATA_DIR = os.path.abspath(argument['DATA_DIR'])
    config = configparser_results(f'{DATA_DIR}/config.ini')

    app_id = config.get('third_party', 'edamam_id')
    app_key = config.get('third_party', 'edamam_key')

    if not app_id or not app_key:
        return False

    params = {'app_id': app_id, 'app_key': app_key, 'ingr': ingredient}
    r = requests.get('https://api.edamam.com/api/nutrition-data', params=params)

    if r.status_code != 200:
        print(f" * ERROR: Could not fetch nutrition data. | Code:({r.status_code} Message:{r.json()['error']})")
        return False

    r_json = r.json()

    nutrition_dict = {
        'nutrients' : {
            'calcium': r_json['totalNutrients'].get('CA'),
            'carbs':r_json['totalNutrients'].get('CHOCDF'),
            'cholesterol':r_json['totalNutrients'].get('CHOLE'),
            'energy':r_json['totalNutrients'].get('ENERC_KCAL'),
            'fat':r_json['totalNutrients'].get('FAT'),
            'fiber':r_json['totalNutrients'].get('FIBTG'),
            'folate_equivalent':r_json['totalNutrients'].get('FOLDFE'),
            'folate_food':r_json['totalNutrients'].get('FOLFD'),
            'iron':r_json['totalNutrients'].get('FE'),
            'magnesium':r_json['totalNutrients'].get('MG'),
            'monounsaturated':r_json['totalNutrients'].get('FAMS'),
            'niacin_b3':r_json['totalNutrients'].get('NIA'),
            'phosphorus':r_json['totalNutrients'].get('P'),
            'polyunsaturated':r_json['totalNutrients'].get('FAPU'),
            'potassium':r_json['totalNutrients'].get('K'),
            'protein':r_json['totalNutrients'].get('PROCNT'),
            'riboflavin_b2':r_json['totalNutrients'].get('RIBF'),
            'saturated':r_json['totalNutrients'].get('FASAT'),
            'sodium':r_json['totalNutrients'].get('NA'),
            'sugars':r_json['totalNutrients'].get('SUGAR'),
            'sugars_added':r_json['totalNutrients'].get('SUGAR.added'),
            'thiamin_b1':r_json['totalNutrients'].get('THIA'),
            'trans':r_json['totalNutrients'].get('FATRN'),
            'vitamin_a':r_json['totalNutrients'].get('VITA_RAE'),
            'vitamin_b12':r_json['totalNutrients'].get('VITB12'),
            'vitamin_b6':r_json['totalNutrients'].get('VITB6A'),
            'vitamin_c':r_json['totalNutrients'].get('VITC'),
            'vitamin_d':r_json['totalNutrients'].get('VITD'),
            'vitamin_e':r_json['totalNutrients'].get('TOCPHA'),
            'vitamin_k':r_json['totalNutrients'].get('VITK1')
        },
        'daily' : {
            'calcium': r_json['totalDaily'].get('CA'),
            'carbs':r_json['totalDaily'].get('CHOCDF'),
            'cholesterol':r_json['totalDaily'].get('CHOLE'),
            'energy':r_json['totalDaily'].get('ENERC_KCAL'),
            'fat':r_json['totalDaily'].get('FAT'),
            'fiber':r_json['totalDaily'].get('FIBTG'),
            'folate_equivalent':r_json['totalDaily'].get('FOLDFE'),
            'folate_food':r_json['totalDaily'].get('FOLFD'),
            'iron':r_json['totalDaily'].get('FE'),
            'magnesium':r_json['totalDaily'].get('MG'),
            'monounsaturated':r_json['totalDaily'].get('FAMS'),
            'niacin_b3':r_json['totalDaily'].get('NIA'),
            'phosphorus':r_json['totalDaily'].get('P'),
            'polyunsaturated':r_json['totalDaily'].get('FAPU'),
            'potassium':r_json['totalDaily'].get('K'),
            'protein':r_json['totalDaily'].get('PROCNT'),
            'riboflavin_b2':r_json['totalDaily'].get('RIBF'),
            'saturated':r_json['totalDaily'].get('FASAT'),
            'sodium':r_json['totalDaily'].get('NA'),
            'sugars':r_json['totalDaily'].get('SUGAR'),
            'sugars_added':r_json['totalDaily'].get('SUGAR.added'),
            'thiamin_b1':r_json['totalDaily'].get('THIA'),
            'trans':r_json['totalDaily'].get('FATRN'),
            'vitamin_a':r_json['totalDaily'].get('VITA_RAE'),
            'vitamin_b12':r_json['totalDaily'].get('VITB12'),
            'vitamin_b6':r_json['totalDaily'].get('VITB6A'),
            'vitamin_c':r_json['totalDaily'].get('VITC'),
            'vitamin_d':r_json['totalDaily'].get('VITD'),
            'vitamin_e':r_json['totalDaily'].get('TOCPHA'),
            'vitamin_k':r_json['totalDaily'].get('VITK1')
        }
    }

    # Only keep the quantity value for each item
    keys = nutrition_dict['nutrients'].keys()
    for section in nutrition_dict:
        for key in keys:
            if nutrition_dict[section][key]:
                nutrition_dict[section][key] = nutrition_dict[section][key]['quantity']

    return nutrition_dict
