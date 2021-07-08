from flask_restful import fields

from extensions import db

instruction_resource_fields = {
    'id': fields.Integer,
    'name': fields.String,
}


class Instruction(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(1000), nullable=False)