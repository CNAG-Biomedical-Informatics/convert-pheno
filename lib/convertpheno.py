import pprint
import json
import pyperler
import pathlib

__author__ = "Manuel Rueda"
__copyright__ = "Copyright 2022-2023, Manuel Rueda - CNAG"
__credits__ = ["None"]
__license__ = "Artistic License 2.0"
__version__ = "0.0.0_alpha"
__maintainer__ = "Manuel Rueda"
__email__ = "manuel.rueda@cnag.crg.eu"
__status__ = "Production"


class PythonBinding:

    def __init__(self, json):
        self.json = json

    def convert_pheno(self):

        # Create interpreter
        i = pyperler.Interpreter()

        ##############################
        # Only if the module WAS NOT #
        # installed from CPAN        #
        ##############################
        # We have to provide the path to <convert-pheno/lib>
        bindir = pathlib.Path(__file__).resolve().parent
        lib_str = "lib '" + str(bindir) + "'"
        i.use(lib_str)

        # Load the module
        CP = i.use('Convert::Pheno')

        # Create object
        convert = CP.new(self.json)

        # The result of the method (e.g. 'pxf2bff()') comes out
        #  as a scalar (Perl hashref)
        # type(hashref) = pyperler.ScalarValue
        hashref = getattr(convert, self.json["method"])()

        # The data structure is accesible via pprint
        # pprint.pprint(hashref)
        # Casting works within print...
        # print(dict(hashref))
        # ... but fails with json.dumps
        # print(json.dumps(dict(hashref)))

        # Trick to serialize it back to a correct Python dictionary
        json_dict = json.loads((pprint.pformat(hashref)).replace("'", '"'))

        # Return dict
        return json_dict
