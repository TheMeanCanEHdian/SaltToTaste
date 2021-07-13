from io import BytesIO
import PIL.Image

from core.database.datasources.database import Database

database_handler = Database()


class ImageDataSource:
    def get_image(self, title_sanitized):
        from main import app
        # Get image name from database
        image_name = database_handler.get_recipe_image(title_sanitized)
        # Create Pillow image
        image = PIL.Image.open(f'{app.config["RECIPE_IMAGES"]}{image_name}')
        return image

    def resize_image(self, image, width, height):
        image.thumbnail((width, height))
        return image
    
    def save_image_as_bytes(self, image):
        img_io = BytesIO()
        image.save(img_io, 'JPEG', quality=70)
        img_io.seek(0)

        return img_io
