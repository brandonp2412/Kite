package nz.presley.kite.iconshowcase;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.TextView;

public final class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        TextView text = new TextView(this);
        text.setGravity(Gravity.CENTER);
        text.setText(getApplicationInfo().loadLabel(getPackageManager()));
        text.setTextColor(Color.DKGRAY);
        text.setTextSize(24);
        setContentView(text);
    }
}
