from flask_wtf import FlaskForm
from flask_wtf.file import FileField
from wtforms import StringField, TextAreaField, IntegerField, FieldList, SubmitField, ValidationError
from wtforms.validators import InputRequired, Length, Optional
from saltToTaste.database_handler import get_recipe_by_title, get_recipe_by_title_f

def uniqueRecipeName(form, field):
    if get_recipe_by_title(field.data):
        raise ValidationError("The recipe name must be unique.")

def uniqueFormattedRecipeName(form, field):
    title_formatted = field.data.replace(" ", "_").lower()
    if get_recipe_by_title_f(title_formatted):
            raise ValidationError("The recipe name must be unique.")

def allowedFileExtensions(form, field):
    allowed_extensions = ['jpg', 'jpeg']
    image_extension = field.data.filename.rsplit('.', 1)[1].lower()
    if image_extension not in allowed_extensions:
        raise ValidationError(f"Image file must be .jpg, or .jpeg.")

class RecipeForm(FlaskForm):
    layout = StringField()
    title = StringField(validators=[InputRequired('A recipe name is required.'), uniqueFormattedRecipeName])
    source = StringField()
    tags = StringField()
    prep = IntegerField(validators=[Optional()])
    cook = IntegerField(validators=[Optional()])
    ready = IntegerField(validators=[Optional()])
    servings = IntegerField(validators=[Optional()])
    calories = IntegerField(validators=[Optional()])
    image = FileField(validators=[Optional(), allowedFileExtensions])
    image_credit = StringField()
    description = TextAreaField()
    notes = FieldList(StringField())
    ingredients = FieldList(StringField())
    directions = FieldList(TextAreaField())
    save = SubmitField()
    save_and_add = SubmitField()
