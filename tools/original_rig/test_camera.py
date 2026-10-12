import unittest
from package_native_review import viewer_point

class NativeCamera(unittest.TestCase):
    def test_height_remains_vertical_after_y_up_export(self):
        self.assertEqual(viewer_point([.2,-.1,1.5]),[.2,1.5,.1])

if __name__=='__main__':unittest.main()
