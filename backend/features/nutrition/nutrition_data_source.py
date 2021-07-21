from datetime import datetime
import requests

from core.database.models.nutrition_model import Nutrition
from core.database.datasources.database import Database
from features.settings.settings_data_source import SettingsDataSource

#TODO: Get directory from argument parser
DATA_DIR = 'assets'

database = Database()
settings_data_source = SettingsDataSource()

app_id = settings_data_source.get_setting('third_party', 'edamam_id')
app_key = settings_data_source.get_setting('third_party', 'edamam_key')


class NutritionDataSource:
    def fetch_nutrition(self, title, ingredient_list, servings=1):
        #TODO: Account for no API entered
        params = {'app_id': app_id, 'app_key': app_key}
        headers = {'Content-Type': 'application/json'}
        ingredient_dict = {
            'title': title,
            'yield': servings,
            'ingr': ingredient_list
        }

        response = requests.post(
            'https://api.edamam.com/api/nutrition-details',
            params=params,
            headers=headers,
            json=ingredient_dict,
        )

        if response.status_code != 200:
            raise Exception('Status Code was not 200')

        response_json = response.json()
        total_nutrients = response_json['totalNutrients']
        total_daily = response_json['totalDaily']
        diet_labels = ', '.join(response_json['dietLabels'])
        health_labels = ', '.join(response_json['healthLabels'])
        cautions = ', '.join(response_json['cautions'])

        nutrition_dict = {
            'weight': response_json.get('totalWeight'),
            'diet_labels': diet_labels,
            'health_labels': health_labels,
            'cautions': cautions,
            'nutrients': {
                'calcium':
                total_nutrients.get('CA').get('quantity')
                if total_nutrients.get('CA') else None,
                'carbs':
                total_nutrients.get('CHOCDF').get('quantity')
                if total_nutrients.get('CHOCDF') else None,
                'cholesterol':
                total_nutrients.get('CHOLE').get('quantity')
                if total_nutrients.get('CHOLE') else None,
                'energy':
                total_nutrients.get('ENERC_KCAL').get('quantity')
                if total_nutrients.get('ENERC_KCAL') else None,
                'fat':
                total_nutrients.get('FAT').get('quantity')
                if total_nutrients.get('FAT') else None,
                'fiber':
                total_nutrients.get('FIBTG').get('quantity')
                if total_nutrients.get('FIBTG') else None,
                'folate_equivalent':
                total_nutrients.get('FOLDFE').get('quantity')
                if total_nutrients.get('FOLDFE') else None,
                'folate_food':
                total_nutrients.get('FOLFD').get('quantity')
                if total_nutrients.get('FOLFD') else None,
                'iron':
                total_nutrients.get('FE').get('quantity')
                if total_nutrients.get('FE') else None,
                'magnesium':
                total_nutrients.get('MG').get('quantity')
                if total_nutrients.get('MG') else None,
                'monounsaturated':
                total_nutrients.get('FAMS').get('quantity')
                if total_nutrients.get('FAMS') else None,
                'niacin_b3':
                total_nutrients.get('NIA').get('quantity')
                if total_nutrients.get('NIA') else None,
                'phosphorus':
                total_nutrients.get('P').get('quantity')
                if total_nutrients.get('P') else None,
                'polyunsaturated':
                total_nutrients.get('FAPU').get('quantity')
                if total_nutrients.get('FAPU') else None,
                'potassium':
                total_nutrients.get('K').get('quantity')
                if total_nutrients.get('K') else None,
                'protein':
                total_nutrients.get('PROCNT').get('quantity')
                if total_nutrients.get('PROCNT') else None,
                'riboflavin_b2':
                total_nutrients.get('RIBF').get('quantity')
                if total_nutrients.get('RIBF') else None,
                'saturated':
                total_nutrients.get('FASAT').get('quantity')
                if total_nutrients.get('FASAT') else None,
                'sodium':
                total_nutrients.get('NA').get('quantity')
                if total_nutrients.get('NA') else None,
                'sugars':
                total_nutrients.get('SUGAR').get('quantity')
                if total_nutrients.get('SUGAR') else None,
                'sugars_added':
                total_nutrients.get('SUGAR.added').get('quantity')
                if total_nutrients.get('SUGAR.added') else None,
                'thiamin_b1':
                total_nutrients.get('THIA').get('quantity')
                if total_nutrients.get('THIA') else None,
                'trans':
                total_nutrients.get('FATRN').get('quantity')
                if total_nutrients.get('FATRN') else None,
                'vitamin_a':
                total_nutrients.get('VITA_RAE').get('quantity')
                if total_nutrients.get('VITA_RAE') else None,
                'vitamin_b12':
                total_nutrients.get('VITB12').get('quantity')
                if total_nutrients.get('VITB12') else None,
                'vitamin_b6':
                total_nutrients.get('VITB6A').get('quantity')
                if total_nutrients.get('VITB6A') else None,
                'vitamin_c':
                total_nutrients.get('VITC').get('quantity')
                if total_nutrients.get('VITC') else None,
                'vitamin_d':
                total_nutrients.get('VITD').get('quantity')
                if total_nutrients.get('VITD') else None,
                'vitamin_e':
                total_nutrients.get('TOCPHA').get('quantity')
                if total_nutrients.get('TOCPHA') else None,
                'vitamin_k':
                total_nutrients.get('VITK1').get('quantity')
                if total_nutrients.get('VITK1') else None
            },
            'daily': {
                'calcium':
                total_daily.get('CA').get('quantity')
                if total_daily.get('CA') else None,
                'carbs':
                total_daily.get('CHOCDF').get('quantity')
                if total_daily.get('CHOCDF') else None,
                'cholesterol':
                total_daily.get('CHOLE').get('quantity')
                if total_daily.get('CHOLE') else None,
                'energy':
                total_daily.get('ENERC_KCAL').get('quantity')
                if total_daily.get('ENERC_KCAL') else None,
                'fat':
                total_daily.get('FAT').get('quantity')
                if total_daily.get('FAT') else None,
                'fiber':
                total_daily.get('FIBTG').get('quantity')
                if total_daily.get('FIBTG') else None,
                'folate_equivalent':
                total_daily.get('FOLDFE').get('quantity')
                if total_daily.get('FOLDFE') else None,
                'folate_food':
                total_daily.get('FOLFD').get('quantity')
                if total_daily.get('FOLFD') else None,
                'iron':
                total_daily.get('FE').get('quantity')
                if total_daily.get('FE') else None,
                'magnesium':
                total_daily.get('MG').get('quantity')
                if total_daily.get('MG') else None,
                'monounsaturated':
                total_daily.get('FAMS').get('quantity')
                if total_daily.get('FAMS') else None,
                'niacin_b3':
                total_daily.get('NIA').get('quantity')
                if total_daily.get('NIA') else None,
                'phosphorus':
                total_daily.get('P').get('quantity')
                if total_daily.get('P') else None,
                'polyunsaturated':
                total_daily.get('FAPU').get('quantity')
                if total_daily.get('FAPU') else None,
                'potassium':
                total_daily.get('K').get('quantity')
                if total_daily.get('K') else None,
                'protein':
                total_daily.get('PROCNT').get('quantity')
                if total_daily.get('PROCNT') else None,
                'riboflavin_b2':
                total_daily.get('RIBF').get('quantity')
                if total_daily.get('RIBF') else None,
                'saturated':
                total_daily.get('FASAT').get('quantity')
                if total_daily.get('FASAT') else None,
                'sodium':
                total_daily.get('NA').get('quantity')
                if total_daily.get('NA') else None,
                'sugars':
                total_daily.get('SUGAR').get('quantity')
                if total_daily.get('SUGAR') else None,
                'sugars_added':
                total_daily.get('SUGAR.added').get('quantity')
                if total_daily.get('SUGAR.added') else None,
                'thiamin_b1':
                total_daily.get('THIA').get('quantity')
                if total_daily.get('THIA') else None,
                'trans':
                total_daily.get('FATRN').get('quantity')
                if total_daily.get('FATRN') else None,
                'vitamin_a':
                total_daily.get('VITA_RAE').get('quantity')
                if total_daily.get('VITA_RAE') else None,
                'vitamin_b12':
                total_daily.get('VITB12').get('quantity')
                if total_daily.get('VITB12') else None,
                'vitamin_b6':
                total_daily.get('VITB6A').get('quantity')
                if total_daily.get('VITB6A') else None,
                'vitamin_c':
                total_daily.get('VITC').get('quantity')
                if total_daily.get('VITC') else None,
                'vitamin_d':
                total_daily.get('VITD').get('quantity')
                if total_daily.get('VITD') else None,
                'vitamin_e':
                total_daily.get('TOCPHA').get('quantity')
                if total_daily.get('TOCPHA') else None,
                'vitamin_k':
                total_daily.get('VITK1').get('quantity')
            }
        }

        return nutrition_dict


class NutritionDB:
    def update_nutrition(self, recipe_id, title, ingredient_list, servings):
        nutrition = Nutrition.query.filter(
            Nutrition.recipe_id == recipe_id).first()

        if not nutrition:
            nutrition = Nutrition(recipe_id=recipe_id)

            try:
                nutrition_data = NutritionDataSource().fetch_nutrition(
                    title,
                    ingredient_list,
                    servings,
                )
                nutrients = nutrition_data['nutrients']
                daily = nutrition_data['daily']

                nutrition.parse_failed = False
                nutrition.last_updated = datetime.now()
                nutrition.weight = nutrition_data.get('weight')
                nutrition.diet_labels = nutrition_data.get('diet_labels')
                nutrition.health_labels = nutrition_data.get('health_labels')
                nutrition.cautions = nutrition_data.get('cautions')
                nutrition.calcium = nutrients.get('calcium')
                nutrition.carbs = nutrients.get('carbs')
                nutrition.cholesterol = nutrients.get('cholesterol')
                nutrition.energy = nutrients.get('energy')
                nutrition.fat = nutrients.get('fat')
                nutrition.fiber = nutrients.get('fiber')
                nutrition.folate_equivalent = nutrients.get(
                    'folate_equivalent')
                nutrition.folate_food = nutrients.get('folate_food')
                nutrition.iron = nutrients.get('iron')
                nutrition.magnesium = nutrients.get('magnesium')
                nutrition.monounsaturated = nutrients.get('monounsaturated')
                nutrition.niacin_b3 = nutrients.get('niacin_b3')
                nutrition.phosphorus = nutrients.get('phosphorus')
                nutrition.polyunsaturated = nutrients.get('polyunsaturated')
                nutrition.potassium = nutrients.get('potassium')
                nutrition.protein = nutrients.get('protein')
                nutrition.riboflavin_b2 = nutrients.get('riboflavin_b2')
                nutrition.saturated = nutrients.get('saturated')
                nutrition.sodium = nutrients.get('sodium')
                nutrition.sugars = nutrients.get('sugars')
                nutrition.sugars_added = nutrients.get('sugars_added')
                nutrition.thiamin_b1 = nutrients.get('thiamin_b1')
                nutrition.trans = nutrients.get('trans')
                nutrition.vitamin_a = nutrients.get('vitamin_a')
                nutrition.vitamin_b12 = nutrients.get('vitamin_b12')
                nutrition.vitamin_b6 = nutrients.get('vitamin_b6')
                nutrition.vitamin_c = nutrients.get('vitamin_c')
                nutrition.vitamin_d = nutrients.get('vitamin_d')
                nutrition.vitamin_e = nutrients.get('vitamin_e')
                nutrition.vitamin_k = nutrients.get('vitamin_k')
                nutrition.calcium_daily = daily.get('calcium')
                nutrition.carbs_daily = daily.get('carbs')
                nutrition.cholesterol_daily = daily.get('cholesterol')
                nutrition.energy_daily = daily.get('energy')
                nutrition.fat_daily = daily.get('fat')
                nutrition.fiber_daily = daily.get('fiber')
                nutrition.folate_equivalent_daily = daily.get(
                    'folate_equivalent')
                nutrition.folate_food_daily = daily.get('folate_food')
                nutrition.iron_daily = daily.get('iron')
                nutrition.magnesium_daily = daily.get('magnesium')
                nutrition.monounsaturated_daily = daily.get('monounsaturated')
                nutrition.niacin_b3_daily = daily.get('niacin_b3')
                nutrition.phosphorus_daily = daily.get('phosphorus')
                nutrition.polyunsaturated_daily = daily.get('polyunsaturated')
                nutrition.potassium_daily = daily.get('potassium')
                nutrition.protein_daily = daily.get('protein')
                nutrition.riboflavin_b2_daily = daily.get('riboflavin_b2')
                nutrition.saturated_daily = daily.get('saturated')
                nutrition.sodium_daily = daily.get('sodium')
                nutrition.sugars_daily = daily.get('sugars')
                nutrition.sugars_added_daily = daily.get('sugars_added')
                nutrition.thiamin_b1_daily = daily.get('thiamin_b1')
                nutrition.trans_daily = daily.get('trans')
                nutrition.vitamin_a_daily = daily.get('vitamin_a')
                nutrition.vitamin_b12_daily = daily.get('vitamin_b12')
                nutrition.vitamin_b6_daily = daily.get('vitamin_b6')
                nutrition.vitamin_c_daily = daily.get('vitamin_c')
                nutrition.vitamin_d_daily = daily.get('vitamin_d')
                nutrition.vitamin_e_daily = daily.get('vitamin_e')
                nutrition.vitamin_k_daily = daily.get('vitamin_k')

            except Exception:
                print(f'Nutrition Error for {title}')
                nutrition.parse_failed = True
                nutrition.last_updated = datetime.now()

            database.add_nutrition(nutrition)

        return nutrition