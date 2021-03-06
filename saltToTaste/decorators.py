from functools import wraps
from flask import current_app, request, abort
from flask_login import current_user
from saltToTaste.configparser_handler import configparser_results
from saltToTaste.database_handler import get_user_by_id

def require_login(view_function):
    @wraps(view_function)
    def decorated_function(*args, **kwargs):
        authentication_enabled = configparser_results(current_app.config['CONFIG_INI']).getboolean('general', 'authentication_enabled')
        user_exists = get_user_by_id(1)
        if authentication_enabled and user_exists and not current_user.is_authenticated:
            return current_app.login_manager.unauthorized()
        else:
            return view_function(*args, **kwargs)
    return decorated_function

def require_login_recipes(view_function):
    @wraps(view_function)
    def decorated_function(*args, **kwargs):
        authentication_enabled = configparser_results(current_app.config['CONFIG_INI']).getboolean('general', 'authentication_enabled')
        user_exists = get_user_by_id(1)
        userless_recipes  = configparser_results(current_app.config['CONFIG_INI']).getboolean('general', 'userless_recipes')
        if (not userless_recipes and (authentication_enabled and user_exists)) and not current_user.is_authenticated:
            return current_app.login_manager.unauthorized()
        else:
            return view_function(*args, **kwargs)
    return decorated_function

def require_apikey(view_function):
    @wraps(view_function)
    def decorated_function(*args, **kwargs):
        api_enabled = configparser_results(current_app.config['CONFIG_INI']).getboolean('general', 'api_enabled')
        api_key = configparser_results(current_app.config['CONFIG_INI']).get('general', 'api_key')
        if api_enabled and request.headers.get('X-Salt-to-Taste-API-Key') and request.headers.get('X-Salt-to-Taste-API-Key') == api_key:
            return view_function(*args, **kwargs)
        else:
            abort(401)
    return decorated_function
