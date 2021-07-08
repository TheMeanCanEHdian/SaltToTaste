from flask_restful import fields

from extensions import db

nutrition_resource_fields = {
    'id': fields.Integer,
    'recipe_id': fields.Integer,
    'last_updated': fields.DateTime,
    'weight': fields.Integer,
    'calcium': fields.Integer,
    'calcium_daily': fields.Integer,
    'carbs': fields.Integer,
    'carbs_daily': fields.Integer,
    'cholesterol': fields.Integer,
    'cholesterol_daily': fields.Integer,
    'energy': fields.Integer,
    'energy_daily': fields.Integer,
    'fat': fields.Integer,
    'fat_daily': fields.Integer,
    'fiber': fields.Integer,
    'fiber_daily': fields.Integer,
    'folate_equivalent': fields.Integer,
    'folate_equivalent_daily': fields.Integer,
    'folate_food': fields.Integer,
    'folate_food_daily': fields.Integer,
    'iron': fields.Integer,
    'iron_daily': fields.Integer,
    'magnesium': fields.Integer,
    'magnesium_daily': fields.Integer,
    'monounsaturated': fields.Integer,
    'monounsaturated_daily': fields.Integer,
    'niacin_b3': fields.Integer,
    'niacin_b3_daily': fields.Integer,
    'phosphorus': fields.Integer,
    'phosphorus_daily': fields.Integer,
    'polyunsaturated': fields.Integer,
    'polyunsaturated_daily': fields.Integer,
    'potassium': fields.Integer,
    'potassium_daily': fields.Integer,
    'protein': fields.Integer,
    'protein_daily': fields.Integer,
    'riboflavin_b2': fields.Integer,
    'riboflavin_b2_daily': fields.Integer,
    'saturated': fields.Integer,
    'saturated_daily': fields.Integer,
    'sodium': fields.Integer,
    'sodium_daily': fields.Integer,
    'sugars': fields.Integer,
    'sugars_daily': fields.Integer,
    'sugars_added': fields.Integer,
    'sugars_added_daily': fields.Integer,
    'thiamin_b1': fields.Integer,
    'thiamin_b1_daily': fields.Integer,
    'trans': fields.Integer,
    'trans_daily': fields.Integer,
    'vitamin_a': fields.Integer,
    'vitamin_a_daily': fields.Integer,
    'vitamin_b12': fields.Integer,
    'vitamin_b12_daily': fields.Integer,
    'vitamin_b6': fields.Integer,
    'vitamin_b6_daily': fields.Integer,
    'vitamin_c': fields.Integer,
    'vitamin_c_daily': fields.Integer,
    'vitamin_d': fields.Integer,
    'vitamin_d_daily': fields.Integer,
    'vitamin_e': fields.Integer,
    'vitamin_e_daily': fields.Integer,
    'vitamin_k': fields.Integer,
    'vitamin_k_daily': fields.Integer,
}


class Nutrition(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    recipe_id = db.Column(db.Integer, unique=True, nullable=False)
    last_updated = db.Column(db.DateTime)
    weight = db.Column(db.Integer)
    calcium = db.Column(db.Integer)
    calcium_daily = db.Column(db.Integer)
    carbs = db.Column(db.Integer)
    carbs_daily = db.Column(db.Integer)
    cholesterol = db.Column(db.Integer)
    cholesterol_daily = db.Column(db.Integer)
    energy = db.Column(db.Integer)
    energy_daily = db.Column(db.Integer)
    fat = db.Column(db.Integer)
    fat_daily = db.Column(db.Integer)
    fiber = db.Column(db.Integer)
    fiber_daily = db.Column(db.Integer)
    folate_equivalent = db.Column(db.Integer)
    folate_equivalent_daily = db.Column(db.Integer)
    folate_food = db.Column(db.Integer)
    folate_food_daily = db.Column(db.Integer)
    iron = db.Column(db.Integer)
    iron_daily = db.Column(db.Integer)
    magnesium = db.Column(db.Integer)
    magnesium_daily = db.Column(db.Integer)
    monounsaturated = db.Column(db.Integer)
    monounsaturated_daily = db.Column(db.Integer)
    niacin_b3 = db.Column(db.Integer)
    niacin_b3_daily = db.Column(db.Integer)
    phosphorus = db.Column(db.Integer)
    phosphorus_daily = db.Column(db.Integer)
    polyunsaturated = db.Column(db.Integer)
    polyunsaturated_daily = db.Column(db.Integer)
    potassium = db.Column(db.Integer)
    potassium_daily = db.Column(db.Integer)
    protein = db.Column(db.Integer)
    protein_daily = db.Column(db.Integer)
    riboflavin_b2 = db.Column(db.Integer)
    riboflavin_b2_daily = db.Column(db.Integer)
    saturated = db.Column(db.Integer)
    saturated_daily = db.Column(db.Integer)
    sodium = db.Column(db.Integer)
    sodium_daily = db.Column(db.Integer)
    sugars = db.Column(db.Integer)
    sugars_daily = db.Column(db.Integer)
    sugars_added = db.Column(db.Integer)
    sugars_added_daily = db.Column(db.Integer)
    thiamin_b1 = db.Column(db.Integer)
    thiamin_b1_daily = db.Column(db.Integer)
    trans = db.Column(db.Integer)
    trans_daily = db.Column(db.Integer)
    vitamin_a = db.Column(db.Integer)
    vitamin_a_daily = db.Column(db.Integer)
    vitamin_b12 = db.Column(db.Integer)
    vitamin_b12_daily = db.Column(db.Integer)
    vitamin_b6 = db.Column(db.Integer)
    vitamin_b6_daily = db.Column(db.Integer)
    vitamin_c = db.Column(db.Integer)
    vitamin_c_daily = db.Column(db.Integer)
    vitamin_d = db.Column(db.Integer)
    vitamin_d_daily = db.Column(db.Integer)
    vitamin_e = db.Column(db.Integer)
    vitamin_e_daily = db.Column(db.Integer)
    vitamin_k = db.Column(db.Integer)
    vitamin_k_daily = db.Column(db.Integer)