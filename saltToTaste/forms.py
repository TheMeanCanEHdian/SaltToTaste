from flask_wtf import FlaskForm
from flask_wtf.file import FileField
from wtforms import StringField, TextAreaField, IntegerField, FieldList, SubmitField, ValidationError
from wtforms.validators import InputRequired, Length, Optional
from saltToTaste.database_handler import get_recipe_by_title, get_recipe_by_title_f, check_for_duplicate_title_f

def uniqueFormattedRecipeNameByID(form, field):
    duplicate = check_for_duplicate_title_f(form.id.data, form.title.data.replace(' ', '-').lower())
    if duplicate:
        raise ValidationError("The recipe name must be unique.")

def uniqueFormattedRecipeName(form, field):
    title_formatted = field.data.replace(" ", "_").lower()
    if get_recipe_by_title_f(title_formatted):
            raise ValidationError("The recipe name must be unique.")

def allowedFileExtensions(form, field):
    allowed_extensions = ['jpg', 'jpeg', 'png']
    image_extension = field.data.filename.rsplit('.', 1)[1].lower()
    if image_extension not in allowed_extensions:
        raise ValidationError(f"Image file must be .jpg, .jpeg, or .png.")

class AddRecipeForm(FlaskForm):
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
    imagecredit = StringField()
    description = TextAreaField()
    notes = FieldList(StringField())
    ingredients = FieldList(StringField())
    directions = FieldList(TextAreaField())
    save = SubmitField()
    save_and_add = SubmitField()

class UpdateRecipeForm(FlaskForm):
    id = IntegerField()
    layout = StringField()
    title = StringField(validators=[InputRequired('A recipe name is required.'), uniqueFormattedRecipeNameByID])
    source = StringField()
    tags = StringField()
    prep = IntegerField(validators=[Optional()])
    cook = IntegerField(validators=[Optional()])
    ready = IntegerField(validators=[Optional()])
    servings = IntegerField(validators=[Optional()])
    calories = IntegerField(validators=[Optional()])
    image = FileField(validators=[Optional(), allowedFileExtensions])
    imagecredit = StringField()
    description = TextAreaField()
    notes = FieldList(StringField())
    ingredients = FieldList(StringField())
    directions = FieldList(TextAreaField())
    update = SubmitField()
